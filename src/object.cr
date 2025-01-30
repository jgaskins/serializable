module Serializable::Object
  macro included
    # JSON
    def self.new(json : ::JSON::PullParser)
      new_from_json_pull_parser json
    end

    def self.from_json(input : String | IO)
      new_from_json_pull_parser ::JSON::PullParser.new(input)
    end

    private def self.new_from_json_pull_parser(pull : ::JSON::PullParser)
      instance = allocate
      instance.initialize with_json_pull_parser: pull
      GC.add_finalizer(instance) if instance.responds_to?(:finalize)
      instance
    end

    # MessagePack
    def self.new(msgpack : ::MessagePack::Unpacker)
      new_from_msgpack_unpacker msgpack
    end

    def self.from_msgpack(input : String | IO | Bytes)
      new_from_msgpack_unpacker ::MessagePack::IOUnpacker.new(input)
    end

    private def self.new_from_msgpack_unpacker(unpacker : ::MessagePack::Unpacker)
      instance = allocate
      instance.initialize with_msgpack_unpacker: unpacker
      GC.add_finalizer(instance) if instance.responds_to?(:finalize)
      instance
    end

    # DB
    def self.new(rs : ::DB::ResultSet)
      instance = allocate
      instance.initialize with_db_result_set: rs
      GC.add_finalizer(instance) if instance.responds_to?(:finalize)
      instance
    end
  end

  protected def after_serialize
  end

  protected def after_deserialize
  end
end
