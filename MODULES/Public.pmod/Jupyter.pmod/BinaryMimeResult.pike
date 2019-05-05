inherit .MimeResult;

string encode() {
  return MIME.encode_base64(result, 1);
}
