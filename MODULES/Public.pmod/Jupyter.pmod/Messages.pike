class Message {

  array zmq_ids = ({});
  string msg_hmac;
  mapping header;
  mapping parent_header;
  mapping metadata;
  mapping content;
  array binary_data;
  object digest;

  string message_type = "message";

  variant protected void create(array _zmq_ids, string _msg_hmac, 
  						mapping _header, mapping _parent_header, 
						mapping _metadata, mapping _content, mixed _binary_data) {
    zmq_ids = _zmq_ids;
	msg_hmac = _msg_hmac;
	header = _header;
	parent_header = _parent_header;
	metadata = _metadata;
	content = _content;
	binary_data = _binary_data;
  }
		
   variant protected  void create(Message req, object _digest) {
     object now = Calendar.ISO_UTC.Fraction();
	 digest = _digest;
	 
	 zmq_ids = req->zmq_ids;
	 parent_header = req->header;

     header = (["msg_type" : message_type,
	 			"username" : req->header->username,
	 			"msg_id": (string)Standards.UUID.make_version4(),
	 			"session": req->header->session,
				"version" : "5.3",
				"date": now->format_ymd() + "T" + now->format_xtod() + "Z",
				]);
				
	}

   array to_messages() {
      int i = 0;
      array x = allocate(7);
	  string json;
	  x[0] = Public.ZeroMQ.Message(zmq_ids[0]);
	  x[1] = Public.ZeroMQ.Message("<IDS|MSG>");
	  json = Standards.JSON.encode(header);
	  digest->update(json);
	  x[3] = Public.ZeroMQ.Message(json);
	  json = Standards.JSON.encode(parent_header);
	  digest->update(json);
	  x[4] = Public.ZeroMQ.Message(json);
	  json = Standards.JSON.encode(metadata);
	  digest->update(json);
	  x[5] = Public.ZeroMQ.Message(json);
	  json = Standards.JSON.encode(content);
	  digest->update(json);
	  x[6] = Public.ZeroMQ.Message(json);
	
      x[2] = Public.ZeroMQ.Message(String.string2hex(digest->digest()));
	
	  return x;  
   }
   				
  string _sprintf(int i, mixed t) {
    return sprintf("Jupyter." + message_type + "(%O)", header);
  }						
						
}
						
						
class KernelInfoRequest {
  inherit Message;
  string message_type = "kernel_info_request";
}

class ExecuteRequest {
  inherit Message;
  string message_type = "execute_request";
}


class ShutdownRequest {
  inherit Message;
  string message_type = "shutdown_request";
}

class CompleteRequest {
  inherit Message;
  string message_type = "complete_request";
}

class CompleteReply {
  inherit Message;
  string message_type = "complete_reply";

  variant protected  void create(CompleteRequest req, object _digest, array matches, int start, int end) {
    ::create(req, _digest);
	metadata = ([]);
     content = (["status": "ok",
	 			  "cursor_start": start,
				  "cursor_end": end,
				  "matches": matches
				]);
   }

}

class ExecuteReply {
  inherit Message;
  string message_type = "execute_reply";

   variant protected  void create(ExecuteRequest req, object _digest, int count, string res) {
    ::create(req, _digest);
	metadata = ([]);
     content = (["status": "ok",
	 			  "execution_count": count,
				]);
   }

   variant protected  void create(ExecuteRequest req, object _digest, string fail_msg) {
    ::create(req, _digest);
	metadata = ([]);
     content = (["status": "error",
	 				"ename": "Evaluation error",
	 			  "evalue": fail_msg,
				  "traceback": ({fail_msg})
				]);
   }
   
}

class ExecuteResult {
  inherit Message;
  string message_type = "execute_result";

   variant protected  void create(ExecuteRequest req, object _digest, int count, string res) {
    ::create(req, _digest);
	metadata = ([]);
     content = (["status": "ok",
	 			  "execution_count": count,
				  "data": (["text/plain": res])
				]);
   }

   variant protected  void create(ExecuteRequest req, object _digest, int count, mapping res) {
    ::create(req, _digest);
	metadata = ([]);
     content = (["status": "ok",
	 			  "execution_count": count,
				  "data": res
				]);
   }
   
}

class Status {
  inherit Message;
  string message_type = "status";

   variant protected void create(ExecuteRequest req, object _digest, string status) {
    ::create(req, _digest);
	metadata = ([]);
     content = ([
	 			  "execution_state": lower_case(status)
				]);
   }
   
}


class Stream {
  inherit Message;
  string message_type = "stream";

   variant protected void create(ExecuteRequest req, object _digest, string name, string data) {
    ::create(req, _digest);
	metadata = ([]);
     content = ([
	 			  "name": lower_case(name),
				  "text": data
				]);
   }
   
}


class Error {
  inherit Message;
  string message_type = "error";

   variant protected  void create(ExecuteRequest req, object _digest, string res) {
    ::create(req, _digest);
	metadata = ([]);
     content = ([
 			  "ename": "Evaluation error",
 			  "evalue": res,
			  "traceback": ({res})
				]);
   }
   
}


class ShutdownReply {
  inherit Message;
  string message_type = "shutdown_reply";

   variant protected  void create(ShutdownRequest req, object _digest) {
    ::create(req, _digest);
	metadata = ([]);		
     content = (["restart": Val.true
				]);
   }
   
}

class KernelInfoReply {
  inherit Message;
  string message_type = "kernel_info_reply";

   variant protected  void create(KernelInfoRequest req, object _digest) {
      ::create(req, _digest);
	  
	  metadata = ([]);
     content = (["protocol_version": "4.0",
	 	//		"implementation": "pike-kernel",
		//		"implementation_version": "0.9",
				"language": "pike",
				"language_version": "8.0", 
/*				"language_info" : (["name": "pike",
						"version": version(),
						"mimetype": "application/pike",
						"file_extension":  ".pike"]),
				"banner": "Pike, yeah!"
				*/
				]);
   }   
}
