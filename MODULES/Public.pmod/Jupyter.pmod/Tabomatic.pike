object obj;
mapping config = ([]);

//! A wrapper for objects that displays array and mapping data as html tables


// TODO
//   prevent double wrapping
//   don't include columns in output if we've excluded them (ie, filter fields through what we actually have)

protected void create(object o, void|mapping _config) {
  obj = o;
  if(_config) config = _config;
}

protected mixed `()(mixed ... args) {
  return wrap(obj(@args));
}

protected mixed `[](mixed a) {
  mixed i = obj[a];
  
  return wrap(i);
}

protected mixed `->(mixed a) {
  if(a == "to_mime_result") return UNDEFINED;
  mixed i = obj[a];
  
  return wrap(i);
}

mixed wrap(mixed i) {
  if(objectp(i) || functionp(i)) return object_program(this)(i, config);
  else if(arrayp(i)) return T(i, config);
  else return i;
}

class T {
  inherit .MimeResult;
  mapping config = ([]);
  protected void create(mixed i, mapping|void _config) {
  werror("T(%O\n)\n", i);
    if(_config) config = _config;
	::create("text/html", i);
  }
  
  protected variant mixed `[](mixed key) {
    return object_program(this)(result[key], config);
  }

  protected variant mixed `[..](int begin, int begin_type, int end, int end_type) {
     return object_program(this)(predef::`[..](result, begin, begin_type, end, end_type), config);
  }
  
  mixed top(int i) {
    if(!i) i = 10;
	if(sizeof(result) < i) i = sizeof(result);
	return object_program(this)(result[0..(i-1)], config);
  }

  mixed bottom(int i) {
    if(!i) i = 10;
	if(sizeof(result) < i) i = sizeof(result);
	return object_program(this)(result[(sizeof(result)-i)..], config);
  }

  mixed fields(array fields) {
    return object_program(this)(result, config + (["fields": fields]));
  }
   

   mixed filter(function f, mixed ... extra) {
     return object_program(this)(predef::filter(result, f, @extra), config);
   }
   
    
  string encode() {
  werror("encode\n");
    String.Buffer buf = String.Buffer();
	buf+=("<table>");
	if(result && ((arrayp(result) && sizeof(result))) || !arrayp(result)) {
	
	  buf+="<tr>";
	  array fields;
	  if(config->fields)
	    fields = config->fields;
	  else {
	    if(objectp(result) || mappingp(result))
		  fields = indices(result);
	    else if(arrayp(result) && (objectp(result[0]) || mappingp(result[0])))
		  fields = indices(result[0]);
	    else if(arrayp(result) && (arrayp(result[0])))
          fields = enumerate(sizeof(result[0]));
		else fields = ({"Value"});
	  }
		
	  foreach(fields;; mixed v)
	  buf+="<th>" + v + "</th>\n";
      buf+="</tr>";
	  
	  
	  if(arrayp(result))
	    foreach(result; int i; mixed r)
		  output(buf, i, fields, r);
	  else 
	      output(buf, 0, fields, result);		  
	  
	}
	
	buf+=("<table>");

    return (string)buf;
  }
  
  void output(String.Buffer buf, int i, array fields, mixed r) {
    if(mappingp(r) || objectp(r) || arrayp(r)) {
      buf->add("<tr>");
      foreach(fields; mixed k; mixed v)
        buf->add("<td>" + r[v] + "</td>\n");
      buf->add("</tr>");
    } else {
      buf->add("<tr>");
      buf->add("<td>" + r + "</td>\n");
      buf->add("</tr>");
  
    }
  }
}