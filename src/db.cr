require "db"

require "./serializable"
require "./object"
require "./error"

# This file was ported from DB::Serializable in the crystal-lang/crystal-db shard
# https://github.com/crystal-lang/crystal-db/blob/532ae075bd810cfd0032b74189ec01fcfba2f355/src/db/serializable.cr

module Serializable::Object
  def initialize(*, with_db_result_set rs : ::DB::ResultSet)
    {% begin %}
      {% properties = {} of Nil => Nil %}
      {% for ivar in @type.instance_vars %}
        {% ann = ivar.annotation(::Serializable::Field) %}
        {% unless ann && ann[:ignore] %}
          {%
            properties[ivar.id] = {
              type:      ivar.type,
              key:       ((ann && ann[:key]) || ivar).id.stringify,
              default:   ivar.default_value,
              nilable:   ivar.type.nilable?,
              converter: ann && ann[:converter],
            }
          %}
        {% end %}
      {% end %}

      {% for name, value in properties %}
        %var{name} = nil
        %found{name} = false
      {% end %}

      rs.each_column do |col_name|
        case col_name
          {% for name, value in properties %}
            when {{value[:key]}}
              %found{name} = true
              begin
                %var{name} =
                  {% if value[:converter] %}
                    {{value[:converter]}}.from_rs(rs)
                  {% elsif value[:nilable] || value[:default] != nil %}
                    rs.read(::Union({{value[:type]}} | Nil))
                  {% else %}
                    rs.read({{value[:type]}})
                  {% end %}
              rescue exc
                ::raise ::DB::MappingException.new(exc.message, self.class.to_s, {{name.stringify}}, cause: exc)
              end
          {% end %}
        else
          rs.read # Advance set, but discard result
          on_unknown_db_column(col_name)
        end
      end

      {% for key, value in properties %}
        {% unless value[:nilable] || value[:default] != nil %}
          if %var{key}.nil? && !%found{key}
            ::raise ::DB::MappingException.new("Missing column {{value[:key].id}}", self.class.to_s, {{key.stringify}})
          end
        {% end %}
      {% end %}

      {% for key, value in properties %}
        {% if value[:nilable] %}
          {% if value[:default] != nil %}
            @{{key}} = %found{key} ? %var{key} : {{value[:default]}}
          {% else %}
            @{{key}} = %var{key}
          {% end %}
        {% elsif value[:default] != nil %}
          @{{key}} = %var{key}.is_a?(Nil) ? {{value[:default]}} : %var{key}
        {% else %}
          @{{key}} = %var{key}.as({{value[:type]}})
        {% end %}
      {% end %}
    {% end %}
  end

  protected def on_unknown_db_column(col_name)
    ::raise ::DB::MappingException.new("Unknown column: #{col_name}", self.class.to_s)
  end

  module NonStrict
    protected def on_unknown_db_column(col_name)
    end
  end
end

class DB::ResultSet
  def read(type : ::Serializable::Object.class)
    type.new self
  end
end
