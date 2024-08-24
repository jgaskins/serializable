module Serializable
  class Error < ::Exception
  end

  class DeserializationError < Error
    getter line_number : Int32
    getter column_number : Int32

    def initialize(message, @line_number, @column_number, cause)
      super message, cause
    end
  end
end
