///|
/// Mutable per-session state shared by serialization and deserialization:
/// the deduplicated-string table and (reserved for later phases) the object
/// reference table. A fresh state is created for every top-level
/// serialize/deserialize call, so ids never leak across calls.
///
/// The tables are allocated lazily on first use, matching desert-rust:
/// sessions that never touch deduplication (the common case for small
/// payloads) pay nothing for them.
pub struct SerializerState {
  priv mut strings_by_id : @hashmap.HashMap[Int32, String]?
  priv mut ids_by_string : @hashmap.HashMap[String, Int32]?
  priv mut last_string_id : Int32
}

///|
/// Result of `store_string` on the serializer side.
priv enum StoreStringResult {
  StringAlreadyStored(Int32)
  StringIsNew(Int32)
}

///|
pub fn SerializerState::new() -> SerializerState {
  { strings_by_id: None, ids_by_string: None, last_string_id: 0, }
}

///|
/// Register `s` in the dedup table. Returns `StringAlreadyStored(id)` when
/// `s` was seen before (with the id it was first stored under), or
/// `StringIsNew(id)` for a first occurrence (ids are assigned consecutively
/// starting from 1, in first-occurrence order).
fn SerializerState::store_string(
  self : SerializerState,
  s : String,
) -> StoreStringResult {
  let ids_by_string = match self.ids_by_string {
    Some(map) => map
    None => {
      let map : @hashmap.HashMap[String, Int32] = @hashmap.HashMap(
        [],
        capacity=64,
      )
      self.ids_by_string = Some(map)
      map
    }
  }
  match ids_by_string.get(s) {
    Some(id) => StringAlreadyStored(id)
    None => {
      let strings_by_id = match self.strings_by_id {
        Some(map) => map
        None => {
          let map : @hashmap.HashMap[Int32, String] = @hashmap.HashMap(
            [],
            capacity=64,
          )
          self.strings_by_id = Some(map)
          map
        }
      }
      let id = self.last_string_id + 1
      self.last_string_id = id
      ids_by_string.set(s, id)
      strings_by_id.set(id, s)
      StringIsNew(id)
    }
  }
}

///|
/// Look up a previously stored string by id. The deserializer registers
/// every string it reads inline, so a miss means a corrupted stream.
fn SerializerState::get_string(self : SerializerState, id : Int32) -> String? {
  match self.strings_by_id {
    Some(strings_by_id) => strings_by_id.get(id)
    None => None
  }
}

///|
/// Register a string that was just read inline (new-occurrence path).
fn SerializerState::store_read_string(
  self : SerializerState,
  s : String,
) -> Unit {
  let _ = self.store_string(s)
}
