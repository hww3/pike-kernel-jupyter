string mime_type;
mixed result;
string string_result;

protected variant void create(string _mime_type, mixed _result) {
  result = _result;
  string_result = sprintf("%O", result);
  mime_type = _mime_type;
}


protected variant void create(string _mime_type, mixed _result, string _string_result) {
  result = _result;
  string_result = _string_result;
  mime_type = _mime_type;
}

mapping to_mime_result() {
  mapping map = ([]);
  map["text/plain"] = string_result;
  map[mime_type] = encode();
  return map;
}

string encode() {
  if(stringp(result))
    return result;
  else throw(Error.Generic("Cannot encode data of type " + sprintf("%O", _typeof(result))));
}