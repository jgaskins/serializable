require "json"
require "uuid/json"

require "./serializable"
require "./object"
require "./error"

# This file was ported from the Crystal stdlib JSON::Serializable
# https://github.com/crystal-lang/crystal/blob/879ec1247/src/json/serialization.cr

module Serializable
  annotation JSON::Options
  end

  module Object
    def initialize(*, with_json_pull_parser pull : ::JSON::PullParser)
      {% begin %}
          {% properties = {} of Nil => Nil %}
          {% for ivar in @type.instance_vars %}
            {% ann = ivar.annotation(::Serializable::Field) %}
            {% unless ann && (ann[:ignore] || ann[:ignore_deserialize]) %}
              {%
                properties[ivar.id] = {
                  key:         ((ann && ann[:key]) || ivar).id.stringify,
                  has_default: ivar.has_default_value?,
                  default:     ivar.default_value,
                  nilable:     ivar.type.nilable?,
                  type:        ivar.type,
                  root:        ann && ann[:root],
                  converter:   ann && ann[:converter],
                  presence:    ann && ann[:presence],
                }
              %}
            {% end %}
          {% end %}

          # `%var`'s type must be exact to avoid type inference issues with
          # recursively defined serializable types
          {% for name, value in properties %}
            %var{name} = uninitialized ::Union({{value[:type]}})
            %found{name} = false
          {% end %}

          %location = pull.location
          begin
            pull.read_begin_object
          rescue exc : ::JSON::ParseException
            raise ::Serializable::JSONDeserializationError.new(exc.message, self.class.to_s, nil, *%location, exc)
          end
          until pull.kind.end_object?
            %key_location = pull.location
            key = pull.read_object_key
            case key
            {% for name, value in properties %}
              when {{value[:key]}}
                begin
                  {% if value[:has_default] || value[:nilable] || value[:root] %}
                    if pull.read_null?
                      {% if value[:nilable] %}
                        %var{name} = nil
                        %found{name} = true
                      {% end %}
                      next
                    end
                  {% end %}

                  %var{name} =
                    {% if value[:root] %} pull.on_key!({{value[:root]}}) do {% else %} begin {% end %}
                      {% if value[:converter] %}
                        {{value[:converter]}}.from_json(pull)
                      {% else %}
                        ::Union({{value[:type]}}).new(pull)
                      {% end %}
                    end
                  %found{name} = true
                rescue exc : ::JSON::ParseException
                  raise ::Serializable::JSONDeserializationError.new(exc.message, self.class.to_s, {{value[:key]}}, *%key_location, exc)
                end
            {% end %}
            else
              on_unknown_json_attribute(pull, key, %key_location)
            end
          end
          pull.read_next

          {% for name, value in properties %}
            if %found{name}
              @{{name}} = %var{name}
            else
              {% unless value[:has_default] || value[:nilable] %}
                raise ::Serializable::JSONDeserializationError.new("Missing JSON attribute: {{value[:key].id}}", self.class.to_s, nil, *%location, nil)
              {% end %}
            end

            {% if value[:presence] %}
              @{{name}}_present = %found{name}
            {% end %}
          {% end %}
        {% end %}
      after_initialize
    end

    protected def after_initialize
    end

    protected def on_unknown_json_attribute(pull, key, key_location)
      pull.skip
    end

    protected def on_to_json(json : ::JSON::Builder)
    end

    def to_json(json : ::JSON::Builder)
      {% begin %}
        {% options = @type.annotation(::Serializable::JSON::Options) %}
        {% emit_nulls = options && options[:emit_nulls] %}

        {% properties = {} of Nil => Nil %}
        {% for ivar in @type.instance_vars %}
          {% ann = ivar.annotation(::Serializable::Field) %}
          {% unless ann && (ann[:ignore] || ann[:ignore_serialize] == true) %}
            {%
              properties[ivar.id] = {
                key:              ((ann && ann[:key]) || ivar).id.stringify,
                root:             ann && ann[:root],
                converter:        ann && ann[:converter],
                emit_null:        (ann && (ann[:emit_null] != nil) ? ann[:emit_null] : emit_nulls),
                ignore_serialize: ann && ann[:ignore_serialize],
              }
            %}
          {% end %}
        {% end %}

        json.object do
          {% for name, value in properties %}
            _{{name}} = @{{name}}

            {% if value[:ignore_serialize] %}
              unless {{ value[:ignore_serialize] }}
            {% end %}

              {% unless value[:emit_null] %}
                unless _{{name}}.nil?
              {% end %}

                json.field({{value[:key]}}) do
                  {% if value[:root] %}
                    {% if value[:emit_null] %}
                      if _{{name}}.nil?
                        nil.to_json(json)
                      else
                    {% end %}

                    json.object do
                      json.field({{value[:root]}}) do
                  {% end %}

                  {% if value[:converter] %}
                    if _{{name}}
                      {{ value[:converter] }}.to_json(_{{name}}, json)
                    else
                      nil.to_json(json)
                    end
                  {% else %}
                    _{{name}}.to_json(json)
                  {% end %}

                  {% if value[:root] %}
                    {% if value[:emit_null] %}
                      end
                    {% end %}
                      end
                    end
                  {% end %}
                end

              {% unless value[:emit_null] %}
                end
              {% end %}
            {% if value[:ignore_serialize] %}
              end
            {% end %}
          {% end %}
          on_to_json(json)
        end
      {% end %}
    end

    module Strict
      protected def on_unknown_json_attribute(pull, key, key_location)
        raise ::Serializable::JSONDeserializationError.new("Unknown JSON attribute: #{key}", self.class.to_s, nil, *key_location, nil)
      end
    end

    module Unmapped
      @[::Serializable::Field(ignore: true)]
      property json_unmapped = Hash(String, ::JSON::Any).new

      protected def on_unknown_json_attribute(pull, key, key_location)
        json_unmapped[key] = begin
          ::JSON::Any.new(pull)
        rescue exc : ::JSON::ParseException
          raise ::Serializable::JSONDeserializationError.new(exc.message, self.class.to_s, key, *key_location, exc)
        end
      end

      protected def on_to_json(json)
        json_unmapped.each do |key, value|
          json.field(key) { value.to_json(json) }
        end
      end
    end

    # Tells this class to decode JSON by using a field as a discriminator.
    #
    # - *field* must be the field name to use as a discriminator
    # - *mapping* must be a hash or named tuple where each key-value pair
    #   maps a discriminator value to a class to deserialize
    #
    # For example:
    #
    # ```
    # require "json"
    #
    # abstract class Shape
    #   include JSON::Serializable
    #
    #   use_json_discriminator "type", {point: Point, circle: Circle}
    #
    #   property type : String
    # end
    #
    # class Point < Shape
    #   property x : Int32
    #   property y : Int32
    # end
    #
    # class Circle < Shape
    #   property x : Int32
    #   property y : Int32
    #   property radius : Int32
    # end
    #
    # Shape.from_json(%({"type": "point", "x": 1, "y": 2}))               # => #<Point:0x10373ae20 @type="point", @x=1, @y=2>
    # Shape.from_json(%({"type": "circle", "x": 1, "y": 2, "radius": 3})) # => #<Circle:0x106a4cea0 @type="circle", @x=1, @y=2, @radius=3>
    # ```
    macro use_json_discriminator(field, mapping)
      {% unless mapping.is_a?(HashLiteral) || mapping.is_a?(NamedTupleLiteral) %}
        {% mapping.raise "Mapping argument must be a HashLiteral or a NamedTupleLiteral, not #{mapping.class_name.id}" %}
      {% end %}

      def self.new(pull : ::JSON::PullParser)
        location = pull.location

        discriminator_value = nil

        # Try to find the discriminator while also getting the raw
        # string value of the parsed JSON, so then we can pass it
        # to the final type.
        json = String.build do |io|
          JSON.build(io) do |builder|
            builder.start_object
            pull.read_object do |key|
              if key == {{field.id.stringify}}
                value_kind = pull.kind
                case value_kind
                when .string?
                  discriminator_value = pull.string_value
                when .int?
                  discriminator_value = pull.int_value
                when .bool?
                  discriminator_value = pull.bool_value
                else
                  raise ::Serializable::JSONDeserializationError.new("JSON discriminator field '{{field.id}}' has an invalid value type of #{value_kind.to_s}", to_s, nil, *location, nil)
                end
                builder.field(key, discriminator_value)
                pull.read_next
              else
                builder.field(key) { pull.read_raw(builder) }
              end
            end
            builder.end_object
          end
        end

        if discriminator_value.nil?
          raise ::Serializable::JSONDeserializationError.new("Missing JSON discriminator field '{{field.id}}'", to_s, nil, *location, nil)
        end

        case discriminator_value
        {% for key, value in mapping %}
          {% if mapping.is_a?(NamedTupleLiteral) %}
            when {{key.id.stringify}}
          {% else %}
            {% if key.is_a?(StringLiteral) %}
              when {{key}}
            {% elsif key.is_a?(NumberLiteral) || key.is_a?(BoolLiteral) %}
              when {{key.id}}
            {% elsif key.is_a?(Path) %}
              when {{key.resolve}}
            {% else %}
              {% key.raise "Mapping keys must be one of StringLiteral, NumberLiteral, BoolLiteral, or Path, not #{key.class_name.id}" %}
            {% end %}
          {% end %}
          {{value.id}}.from_json(json)
        {% end %}
        else
          raise ::Serializable::JSONDeserializationError.new("Unknown '{{field.id}}' discriminator value: #{discriminator_value.inspect}", to_s, nil, *location, nil)
        end
      end
    end
  end

  class JSONDeserializationError < DeserializationError
    getter klass : String
    getter attribute : String?

    def initialize(message : String?, @klass : String, @attribute : String?, line_number : Int32, column_number : Int32, cause)
      message = String.build do |io|
        io << message
        io << "\n  parsing "
        io << klass
        if attribute = @attribute
          io << '#' << attribute
        end
      end
      super(message, line_number, column_number, cause)
      if cause
        @line_number, @column_number = cause.location
      end
    end
  end
end
