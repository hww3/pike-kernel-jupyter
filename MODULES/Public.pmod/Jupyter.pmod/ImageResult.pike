inherit .MimeResult;


protected variant void create(Image.Image _result) {
  result = _result;
  string_result = sprintf("%O", result);
  mime_type = "image/png";
}

string encode() {
  return MIME.encode_base64(Image.PNG.encode(result), 1);
}
