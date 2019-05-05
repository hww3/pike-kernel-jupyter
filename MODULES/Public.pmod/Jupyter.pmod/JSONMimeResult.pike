inherit .MimeResult;

protected variant void create(mixed d) {
  mime_type = "application/json";
  result = d;
  string_result = Standards.JSON.encode(d);
}

string encode() {
  return (result);
}