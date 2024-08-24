require "serializable/json"
require "serializable/msgpack"
require "serializable/db"
require "pg"
require "uuid"

struct User
  include Serializable::Object

  getter id : UUID
  getter name : String
  @[Serializable::Field(converter: String::UpcaseConverter)]
  getter capitalized_string : String
  @[Serializable::Field(converter: Time::NanosecondsConverter)]
  getter created_at : Time

  def initialize(*, @id = UUID.v7, @name, @capitalized_string, @created_at)
  end

  # Strictly for the example
  def to_db_args
    {
      id.to_s,
      name,
      capitalized_string,
      created_at.to_rfc3339(fraction_digits: 9),
    }
  end
end

pg = DB.open("postgres:///")
user = User.new(
  name: "Jamie",
  capitalized_string: "FOO bar",
  created_at: Time.utc,
)
pp(
  canonical_user: user,
  from_msgpack: User.from_msgpack(user.to_msgpack),
  from_json: User.from_json(user.to_json),
  from_db: pg.query_one(
    <<-SQL,
      SELECT
        $1::uuid AS id,
        $2::text AS name,
        lower($3::text) AS capitalized_string,
        $4::timestamptz AS created_at
      SQL
    *user.to_db_args,
    as: User,
  ),
)
# {canonical_user:
#   User(
#    @capitalized_string="FOO bar",
#    @created_at=2024-08-24 04:52:53.955393000 UTC,
#    @id=UUID(019182ba-ec43-74a7-820a-5cc50c2f0a61),
#    @name="Jamie"),
#  from_msgpack:
#   User(
#    @capitalized_string="FOO BAR",
#    @created_at=2024-08-24 04:52:53.955393000 UTC,
#    @id=UUID(019182ba-ec43-74a7-820a-5cc50c2f0a61),
#    @name="Jamie"),
#  from_json:
#   User(
#    @capitalized_string="FOO BAR",
#    @created_at=2024-08-24 04:52:53.955393000 UTC,
#    @id=UUID(019182ba-ec43-74a7-820a-5cc50c2f0a61),
#    @name="Jamie"),
#  from_db:
#   User(
#    @capitalized_string="FOO BAR",
#    @created_at=2024-08-23 23:52:53.955393000 -05:00 America/Chicago,
#    @id=UUID(019182ba-ec43-74a7-820a-5cc50c2f0a61),
#    @name="Jamie")}

module String::UpcaseConverter
  extend self

  def from_json(json : JSON::PullParser) : String
    json.read_string.upcase
  end

  def to_json(string : String, json : JSON::Builder) : Nil
    json.string string.downcase
  end

  def from_msgpack(msgpack : MessagePack::Unpacker) : String
    pp msgpack.read_string.upcase
  end

  def to_msgpack(string : String, msgpack : MessagePack::Packer) : Nil
    msgpack.write string.downcase
  end

  def from_rs(rs : DB::ResultSet)
    rs.read(String).upcase
  end
end

module Time::NanosecondsConverter
  extend self

  def to_json(time : Time, json : JSON::Builder) : Nil
    json.string do |io|
      time.to_rfc3339 io, fraction_digits: 9
    end
  end

  def from_json(json : JSON::PullParser) : Time
    Time.new(json)
  end

  def to_msgpack(time : Time, msgpack : MessagePack::Packer) : Nil
    msgpack.write_array_start 2
    msgpack.write time.@seconds
    msgpack.write time.@nanoseconds
  end

  def from_msgpack(msgpack : MessagePack::Unpacker) : Time
    seconds, nanoseconds = Tuple(Int64, Int32).new(msgpack)
    Time.new(
      seconds: seconds,
      nanoseconds: nanoseconds,
      location: Time::Location::UTC,
    )
  end

  def from_rs(rs : DB::ResultSet) : Time
    rs.read Time
  end
end
