object obj;
mapping config = ([]);

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
  //werror("T(%O\n)\n", i);
    if(_config) config = _config;
	::create("text/html", i);
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
    String.Buffer buf = String.Buffer();
	buf+=("<table>");
	if(sizeof(result)) {
	
	  buf+="<tr>";
	  array fields;
	  if(config->fields)
	    fields = config->fields;
	  else 
	    fields = indices(result[0]);
	  foreach(fields;; mixed v)
	  buf+="<th>" + v + "</th>\n";
      buf+="</tr>";
	  
	  foreach(result; int i;  mixed r) {
	     if(mappingp(r)) {
	       buf+="<tr>";
           foreach(fields; mixed k; mixed v)
		     buf += ("<td>" + r[v] + "</td>\n");
	       buf+="</tr>";

	     } else if(arrayp(r)) {
	     } else {
	     
	     }
	  }
	}
	
	buf+=("<table>");

    return (string)buf;
  }  
}