require "msgpack"
require "uuid"

require "./serializable"
require "./object"
require "./error"

# This file was ported from MessagePack::Serializable in the crystal-community/msgpack-crystal shard
# https://github.com/crystal-community/msgpack-crystal/blob/8de33411c38901f44ca74a7f32e1ad82a38e0b84/src/message_pack/serializable.cr

module Serializable::Object
  def initialize(*, with_msgpack_unpacker pull : ::MessagePack::Unpacker)
    {% begin %}
      {% properties = {} of Nil => Nil %}
      {% for ivar in @type.instance_vars %}
        {% ann = ivar.annotation(::Serializable::Field) %}
        {% unless ann && ann[:ignore] %}
          {%
            properties[ivar.id] = {
              type:        ivar.type,
              key:         ((ann && ann[:key]) || ivar).id.stringify,
              has_default: ivar.has_default_value?,
              default:     ivar.default_value,
              nilable:     ivar.type.nilable?,
              converter:   ann && ann[:converter],
            }
          %}
        {% end %}
      {% end %}

      {% for name, value in properties %}
        %var{name} = nil
        %found{name} = nil
      {% end %}

      token = pull.current_token
      pull.consume_hash do
        %key = Bytes.new(pull)
        {% if properties.size > 0 %}
          case %key
          {% for name, value in properties %}
            when {{value[:key]}}.to_slice
              %found{name} = true
              %var{name} =
                {% if value[:nilable] || value[:has_default] %} pull.read_nil_or do {% end %}

                {% if value[:converter] %}
                  {{value[:converter]}}.from_msgpack(pull)
                {% else %}
                  ::Union({{value[:type]}}).new(pull)
                {% end %}

                {% if value[:nilable] || value[:has_default] %} end {% end %}
          {% end %}
          else
            on_unknown_msgpack_attribute(pull, %key)
          end
        {% else %}
          on_unknown_msgpack_attribute(pull, %key)
        {% end %}
      end

      {% for name, value in properties %}
        {% unless value[:nilable] || value[:has_default] %}
          if %var{name}.nil? && !%found{name} && !::Union({{value[:type]}}).nilable?
            raise ::MessagePack::TypeCastError.new("Missing msgpack attribute: {{value[:key].id}}", token.byte_number)
          end
        {% end %}

        {% if value[:nilable] %}
          {% if value[:has_default] != nil %}
            if %found{name} && !%var{name}.nil?
              @{{name}} = %var{name}
            end
          {% else %}
            @{{name}} = %var{name}
          {% end %}
        {% elsif value[:has_default] %}
          if %found{name} && !%var{name}.nil?
            @{{name}} = %var{name}
          end
        {% else %}
          @{{name}} = (%var{name}).as({{value[:type]}})
        {% end %}
      {% end %}
    {% end %}
    after_initialize
  end

  macro use_msgpack_discriminator(field, mapping)
    {% unless mapping.is_a?(HashLiteral) || mapping.is_a?(NamedTupleLiteral) %}
      {% mapping.raise "mapping argument must be a HashLiteral or a NamedTupleLiteral, not #{mapping.class_name.id}" %}
    {% end %}

    def self.new(pull : ::MessagePack::Unpacker)
      node = pull.read_node
      pull2 = MessagePack::NodeUnpacker.new(node)
      discriminator_value = nil
      pull2.consume_table do |key|
        if key == {{field.id.stringify}}
          case token = pull2.read_token
          when MessagePack::Token::IntT, MessagePack::Token::StringT, MessagePack::Token::BoolT
            discriminator_value = token.value
            break
          else
            # nothing more to do
            raise ::MessagePack::TypeCastError.new("Msgpack discriminator field '{{field.id}}' has an invalid value type of #{MessagePack::Token.to_s(token)}", token.byte_number)
          end
        else
          pull2.skip_value
        end
      end

      unless discriminator_value
        raise ::MessagePack::UnpackError.new("Missing Msgpack discriminator field '{{field.id}}'", 0)
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
            {% key.raise "mapping keys must be one of StringLiteral, NumberLiteral, BoolLiteral, or Path, not #{key.class_name.id}" %}
          {% end %}
        {% end %}
        {{value.id}}.new(__pull_for_msgpack_serializable: MessagePack::NodeUnpacker.new(node))
      {% end %}
      else
        raise ::MessagePack::UnpackError.new("Unknown '{{field.id}}' discriminator value: #{discriminator_value.inspect}", 0)
      end
    end
  end

  protected def on_unknown_msgpack_attribute(pull, key : Bytes)
    pull.skip_value
  end

  protected def additional_write_fields_count
    0
  end

  protected def on_to_msgpack(packer : ::MessagePack::Packer)
  end

  def to_msgpack(packer : ::MessagePack::Packer)
    {% begin %}
      {% options = @type.annotation(::MessagePack::Serializable::Options) %}
      {% emit_nulls = options && options[:emit_nulls] %}

      {% properties = {} of Nil => Nil %}
      {% for ivar in @type.instance_vars %}
        {% ann = ivar.annotation(::Serializable::Field) %}
        {% unless ann && ann[:ignore] %}
          {%
            properties[ivar.id] = {
              type:      ivar.type,
              key:       ((ann && ann[:key]) || ivar).id.stringify,
              converter: ann && ann[:converter],
              emit_null: (ann && (ann[:emit_null] != nil) ? ann[:emit_null] : emit_nulls),
            }
          %}
        {% end %}
      {% end %}

      ready_fields = additional_write_fields_count

      {% for name, value in properties %}
        _{{name}} = @{{name}}

        {% if value[:emit_null] %}
          ready_fields += 1
        {% else %}
          ready_fields += 1 unless _{{name}}.nil?
        {% end %}
      {% end %}

      packer.write_hash_start(ready_fields)

      {% for name, value in properties %}
        unless _{{name}}.nil?
          packer.write({{value[:key]}})
          {% if value[:converter] %}
            {{ value[:converter] }}.to_msgpack(_{{name}}, packer)
          {% else %}
            _{{name}}.to_msgpack(packer)
          {% end %}
        else
          {% if value[:emit_null] %}
            packer.write({{value[:key]}})
            nil.to_msgpack(packer)
          {% end %}
        end
      {% end %}

      on_to_msgpack(packer)
    {% end %}
  end

  module Strict
    protected def on_unknown_msgpack_attribute(pull, key)
      raise ::MessagePack::TypeCastError.new("Unknown msgpack attribute: #{String.new(key)}")
    end
  end

  module Unmapped
    @[::Serializable::Field(ignore: true)]
    property msgpack_unmapped = Hash(String, ::MessagePack::Type).new

    protected def on_unknown_msgpack_attribute(pull, key)
      msgpack_unmapped[String.new(key)] = pull.read
    end

    protected def additional_write_fields_count
      msgpack_unmapped.size
    end

    protected def on_to_msgpack(packer)
      msgpack_unmapped.each do |key, value|
        key.to_msgpack(packer)
        value.to_msgpack(packer)
      end
    end
  end
end

struct MessagePack::Packer
  def write(uuid : UUID)
    write uuid.bytes.to_slice
  end
end

def UUID.new(unpacker : MessagePack::Unpacker)
  new unpacker.read_bytes
end
