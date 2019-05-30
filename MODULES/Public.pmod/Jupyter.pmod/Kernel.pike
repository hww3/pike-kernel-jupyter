import Public.ZeroMQ;

mapping config;

Context context;

Socket shell;
Socket iopub;
Socket stdin;
Socket control;
Socket heartbeat;

Socket local_ipc;
Socket ipc;

Poll poll;
Poll hb_poll;

Thread.Thread hb_poll_thread;
Thread.Thread poll_thread;

object hmac;

object time = System.Time();
 
mapping awaiting_answers = ([]);
mapping sessions = ([]);

int keep_going = 1;

protected void create(mapping _config) {
  werror("Starting Kernel with configuration=%O\n", _config);
  config = _config;
  
  if(config->signature_scheme && config->signature_scheme != "") {
    if(config->signature_scheme == "hmac-sha256")
	  hmac = Crypto.SHA256.HMAC;
	else
	  throw(Error.Generic("Invalid HMAC scheme " + config->signature_scheme + ".\n"));
  } 
  
  call_out(create_sockets, 0);
}

void create_poll_threads() {
  werror("Starting poller 1\n");
  poll_thread = Thread.Thread(run_poller, poll);
  werror("Starting poller 2\n");
  hb_poll_thread = Thread.Thread(run_poller, hb_poll);
}

void create_sockets() {
  int rv;
  
  context = Context();
  
  poll = Poll();
  hb_poll = Poll();
  
  local_ipc = Socket(context, SUB);
  rv = local_ipc->connect("inproc://hilfe-completion");
  if(rv < 0) { werror("binding to socket returned value %d: %s\n", rv, Public.ZeroMQ.strerror(Public.ZeroMQ.errno())); }
  local_ipc->set_option(SUBSCRIBE, "");
  
  poll->add_socket(local_ipc, completion_recv);
    
  shell = Socket(context, ROUTER);
  rv = shell->bind(config->transport + "://" + config->ip + ":" + config->shell_port);
  if(rv < 0) { werror("binding to socket returned value %d: %s\n", rv, Public.ZeroMQ.strerror(Public.ZeroMQ.errno())); }
  poll->add_socket(shell, shell_recv);
  iopub = Socket(context, PUB);
  rv = iopub->bind(config->transport + "://" + config->ip + ":" + config->iopub_port);
  if(rv < 0) { werror("binding to socket returned value %d: %s\n", rv, Public.ZeroMQ.strerror(Public.ZeroMQ.errno())); }
  stdin = Socket(context, ROUTER);
  rv = stdin->bind(config->transport + "://" + config->ip + ":" + config->stdin_port);
  if(rv < 0) { werror("binding to socket returned value %d: %s\n", rv, Public.ZeroMQ.strerror(Public.ZeroMQ.errno())); }
  control = Socket(context, ROUTER);
  rv = control->bind(config->transport + "://" + config->ip + ":" + config->control_port);
  if(rv < 0) { werror("binding to socket returned value %d: %s\n", rv, Public.ZeroMQ.strerror(Public.ZeroMQ.errno())); }
  poll->add_socket(control, control_recv);
  heartbeat = Socket(context, REP);
  rv = heartbeat->bind(config->transport + "://" + config->ip + ":" + config->hb_port);
  if(rv < 0) { werror("binding to socket returned value %d: %s\n", rv, Public.ZeroMQ.strerror(Public.ZeroMQ.errno())); }
  hb_poll->add_socket(heartbeat, hb_recv);
  
  call_out(create_poll_threads, 0);
}

void run_poller(object poller) {
  int rv;
  
  werror("Starting poll thread.\n");
  do {
    rv = poller->poll(1.0);
	//werror("Poll completed with rv=%d\n", rv);
  } while (rv >= 0 && keep_going);
  
  werror("Poller exiting.\n");
}

void shell_recv(object socket, mixed ... args) {
  werror("%s shell_recv: %O => %O\n", getTime(), socket, args);
  object message = parse_message(args);
  if(message) {
    handle_message(socket, message);
    werror("%s dispatched.\n", getTime());
  } else {
    werror("ignored.\n");
  }
}

int i;

void completion_recv(object socket, mixed ... args) {
  werror("%s completion_recv: %O => %O\n", getTime(), socket, args);
  
  if(sizeof(args) == 2) { // status change
     if(args[0]->dta == "DIED") {
	    sessions[args[1]->dta]->ipc = 0;
	    sessions[args[1]->dta]->runner = 0;
 	 }
	 return;
  }
  //werror("awaiting_answers: %O", indices(awaiting_answers));
  mixed a = awaiting_answers[args[0]->dta];
  if(a) {
  //werror("got matching request\n");
      object digest;
    if(hmac) digest = hmac(config->key);
  
    // a "successful" evaluation has 3 parts: the msg id we're replying to, the statement number or type and the response.
    if(args[1]->dta == "error") {
      object msg = .Messages.ExecuteReply(a->msg, digest, args[2]->dta);
      array m = msg->to_messages();
      //werror("reply: %O\n", m);
      shell->send(m);

      msg = .Messages.Error(a->msg, digest, args[2]->dta);
      m = msg->to_messages();
      //werror("reply: %O\n", m);
      iopub->send(m);
      //werror("sent\n");	
	
	} else if(args[1]->dta == "stdout") {
	//werror("sending stdout to notebook.\n");
	  iopub->send(.Messages.Stream(a->msg, digest, "stdout", args[2]->dta)->to_messages());
	  return;
	} else if(args[1]->dta == "stderr") {
	// werror("sending stderr to notebook.\n");
	  iopub->send(.Messages.Stream(a->msg, digest, "stderr", args[2]->dta)->to_messages());
	  return;
	} else if(args[1]->dta == "complete") {
      object msg = .Messages.ExecuteReply(a->msg, digest, sessions[a->msg->header->session]->last_result, args[2]->dta);
      array m = msg->to_messages();
      //werror("reply: %O\n", m);
      shell->send(m);
	} else if(args[1]->dta == "completions") {
      object msg = .Messages.CompleteReply(a->msg, digest, Standards.JSON.decode(args[2]->dta), a->msg->content->cursor_pos, a->msg->content->cursor_pos);
      array m = msg->to_messages();
      //werror("reply: %O\n", m);
      shell->send(m);	
	} else if(args[1]->dta == "result_object") {
	   //werror("sending object result to notebook.\n");
	   mapping data = Standards.JSON.decode(args[2]->dta);
	   int execution_count = (int)(data->execution_count);
	   if(!execution_count) execution_count = sessions[a->msg->header->session]->last_result;
	   sessions[a->msg->header->session]->last_result = execution_count;
	   
	   m_delete(data, "execution_count");
       object msg = .Messages.ExecuteResult(a->msg, digest, execution_count, data);
       array m = msg->to_messages();
      // werror("reply: %O\n", m);
       iopub->send(m);
      // werror("sent\n");	
       return;	
	}
	else if(sizeof(args) == 3) {
	  // werror("sending result to notebook.\n");
	   int ec = (int)(args[1]->dta);
	   if(!ec) ec = sessions[a->msg->header->session]->last_result;
	   sessions[a->msg->header->session]->last_result = ec;
       object msg = .Messages.ExecuteResult(a->msg, digest, ec, args[2]->dta);
       array m = msg->to_messages();
       werror("reply: %O\n", m);
       iopub->send(m);
       // werror("sent\n");	
       return;
    } else {
	  werror("ERROR: Received unknown message from completion handler: %O.\n", args);
	}
  
    // werror("sending idle.\n");
  	iopub->send(.Messages.Status(a->msg, digest, "idle")->to_messages());
  }
  m_delete(awaiting_answers, args[0]->dta);
  // werror("awaiting_answers: %O", indices(awaiting_answers));
	  
}

void control_recv(object socket, mixed ... args) {
  werror("%s control_recv: %O => %O\n", getTime(), socket, args);
  object message = parse_message(args);
  if(message) { 
    handle_message(socket, message);
  //  werror("dispatched.\n");
  } else {
  //  werror("ignored.\n");
  }
}

void hb_recv(object socket, mixed ... args) {
 // werror("hb_recv: %O => %O\n", socket, args);
  socket->send(Message("pong"), 0);
}

void handle_message(object socket, .Messages.Message msg) {
    object digest;
  if(hmac) digest = hmac(config->key);
	werror("%s handle_message: %O\n", getTime(), msg);
	
    if(msg->message_type == "kernel_info_request") {
  //	werror("preparing response\n");
  	  iopub->send(.Messages.Status(msg, digest, "busy")->to_messages());
	  object r = .Messages.KernelInfoReply(msg, digest);
	  array m = r->to_messages();
	//  werror("reply: %O\n", m);
	  socket->send(m);
	  werror("sent\n");
  	  iopub->send(.Messages.Status(msg, digest, "idle")->to_messages());
	} else if(msg->message_type == "shutdown_request") {
	  iopub->send(.Messages.Status(msg, digest, "busy")->to_messages());

	  object r = .Messages.ShutdownReply(msg, digest);
	  array m = r->to_messages();
	  // werror("reply: %O\n", m);
	  socket->send(m);
	  call_out(exit, 1, 0);
	  // werror("sent\n");
  	  iopub->send(.Messages.Status(msg, digest, "idle")->to_messages());
	  
	 } else if(msg->message_type == "execute_request") {
  	  
	   iopub->send(.Messages.Status(msg, digest, "busy")->to_messages());
	
       create_session_if_necessary(msg);	
	  
	   awaiting_answers[msg->header->msg_id] = (["msg": msg]);
	   sessions[msg->header->session]->runner->queue_request(msg);
	} else if(msg->message_type == "complete_request") {
	   iopub->send(.Messages.Status(msg, digest, "busy")->to_messages());
       create_session_if_necessary(msg);	
	  
	   awaiting_answers[msg->header->msg_id] = (["msg": msg]);
	   sessions[msg->header->session]->runner->queue_request(msg);
	}
}

void create_session_if_necessary(.Messages.Message msg) {
	if(!sessions[msg->header->session]) {
	  int rv;
	  werror("creating new session\n");
 	  object ipc = Socket(context, PUB);
      rv = ipc->bind("inproc://hilfe-completion");
      if(rv < 0) { 
 	    werror("binding to socket returned value %d: %s\n", rv, Public.ZeroMQ.strerror(Public.ZeroMQ.errno())); 
	  }
		
	  object hilfeRunner = .HilfeRunner(ipc, msg->header->session);
	  sessions[msg->header->session] = ([ "runner": hilfeRunner, "ipc": ipc, "last_result": 1]);
	}
}

.Messages.Message parse_message(array parts) {
  array zmq_ids = ({});
  string msg_hmac;
  mapping header;
  mapping parent_header;
  mapping metadata;
  mapping content;
  array binary_data;

  int have_header;
  object digest;
  
  foreach(parts; int i; object part) {
     if(!have_header) {
	    if(part->dta == "<IDS|MSG>") {
		  have_header = 1; 
		  continue;
	    } else {
		  zmq_ids += ({part->dta});
		}
   	 } else if(!msg_hmac) {
  	   if(hmac && !part->dta)
	     throw(Error.Generic("Expecting a HMAC but none received.\n"));
   	   msg_hmac = part->dta;
	   digest = hmac(config->key);
   	   continue;
	 } else if(!header) {
	   header = Standards.JSON.decode(part->dta);
	   if(digest) digest->update(part->dta);
	   continue;
	 } else if(!parent_header) {
	   parent_header = Standards.JSON.decode(part->dta);
	   if(digest) digest->update(part->dta);
	   continue;
	 } else if(!metadata) {
	   metadata = Standards.JSON.decode(part->dta);
	   if(digest) digest->update(part->dta);
	   continue;
	 } else if(!content) {
	   content = Standards.JSON.decode(part->dta);
	   if(digest) digest->update(part->dta);
	   continue;
	 } else {
	 	if(!binary_data) binary_data = ({part->dta});
		else binary_data += ({part->dta});
	 }
  }
  
 // validate hmac
 if(digest) {
   string h = String.string2hex(digest->digest());
   //werror("our hmac=%O", h);
   if(h != msg_hmac) throw(Error.Generic("HMAC comparison failed. Expected " + msg_hmac +", got " + h + ".\n"));
   // else werror("HMAC looks good. Message is authentic.\n");
 }
  
  //werror("zmq_ids=%O, hmac=%O, digest=%O, header=%O, parent_header=%O, metadata=%O, content=%O, binary_data=%O\n",
  //			zmq_ids, msg_hmac, digest, header, parent_header, metadata, content, binary_data);
			
  object message;
  
  switch(header->msg_type) {
    case "kernel_info_request":
      message = .Messages.KernelInfoRequest(zmq_ids, msg_hmac, header, parent_header, metadata, content, binary_data);

	  break;
    case "shutdown_request":
      message = .Messages.ShutdownRequest(zmq_ids, msg_hmac, header, parent_header, metadata, content, binary_data);
	  break;

    case "execute_request":
      message = .Messages.ExecuteRequest(zmq_ids, msg_hmac, header, parent_header, metadata, content, binary_data);
	  break;

    case "complete_request":
      message = .Messages.CompleteRequest(zmq_ids, msg_hmac, header, parent_header, metadata, content, binary_data);
	  break;
	  
	default:
	  werror("Unknown message type " + header->msg_type +".\n");
	  break;
  }
  
  werror("%s message=%O\n", getTime(), message);
  return message;
}

string getTime() {
   return replace(ctime(time->sec), "\n", ".") + sprintf("%03d", time->usec/1000);
}