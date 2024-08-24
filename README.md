# Serializable

Unified serialization/deserialization interface.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     serializable:
       github: jgaskins/serializable
   ```

2. Run `shards install`

## Usage

In your serializable objects, include the `Serializable::Object` mixin:

```crystal
require "serializable/object"

struct Post
  include Serializable::Object

  getter id : UUID
  getter title : String
  getter body : String
  getter author_id : UUID
  getter author_display_name : String
  getter published_at : Time
end
```

Make sure you require any of the adapters needed for the serialization formats
you are using:

```crystal
require "serializable/json"
require "serializable/msgpack"
require "serializable/db"
```

These adapters add the `from_#{format}` / `to_#{format}` methods. If you only need JSON, you can simply require the `serializable/json` adapter.

If you need additional serialization formats, please open an issue or a PR.

## Development

This is still early days for this shard. The development process hasn't been ironed out yet.

## Contributing

1. Fork it (<https://github.com/jgaskins/serializable/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Jamie Gaskins](https://github.com/jgaskins) - creator and maintainer
