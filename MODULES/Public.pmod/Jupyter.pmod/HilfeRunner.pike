import Public.ZeroMQ;

object hilfe;
object infile, outfile, errfile;
object myinfile, myoutfile, myerrfile;

object queue = ADT.Queue();
object ipc; // inproc pair
object remote_ipc;
Process.Process remote;
object poll;
object context;
Thread.Thread poll_thread;
int waiting = 0;
mixed current_message;
int keep_going = 1;
int started = 0;
string session_id;

void create(object ipc_socket, string session) {
  ipc = ipc_socket;
  session_id = session;
  werror("STARTING REMOTE HILFE\n");
  infile = Stdio.File();
  outfile = Stdio.File();
  errfile = Stdio.File();
 
  myinfile = infile->pipe();
  myoutfile = outfile->pipe();
  myerrfile = errfile->pipe();
  
  myoutfile->set_nonblocking();
  myoutfile->set_read_callback(read_stdout);

  myerrfile->set_nonblocking();
  myerrfile->set_read_callback(read_stderr);

  int port = 30000 + random(1000);
  
  context = Context();
  poll = Poll();
  remote_ipc = Socket(context, PAIR);
  werror("HilfeRunner binding on tcp://localhost:" + port + "\n");
  remote_ipc->bind("tcp://*:" + port);
  remote = Process.spawn_pike(({"-x", "pike_kernel", "-r", "" + port, "-p", "" + getpid()}), (["callback": process_state_cb, "stdin": infile, "stdout": outfile, "stderr": errfile]));
  poll->add_socket(remote_ipc, ipc_recv, ipc_send);
  call_out(create_poll_threads, 0);
  
}

void process_state_cb(Process.Process process) {
  if(process->status() > 0) { 
    werror("WARNING: RemoteHilfe process exited or stopped.\n");
	keep_going = 0;
	poll_thread->kill();
    ipc->send(({Message("DIED"), Message(session_id)}));
  }
}

void ipc_send(object socket) {
 // werror("Sending areyouthereyet\n");
 // ipc->send(Message("AREYOUTHEREYET"), 0);
}

void ipc_recv(object socket, mixed ... messages) {
  werror("IPC: %O\n", messages);
  mixed msg = current_message;
  
  if(sizeof(messages) > 1 && messages[1]->dta != msg->message->header->msg_id) {
    werror("WARNING: Received a message from RemoteHilfe for different request");
  } 
  
  if(messages[0]->dta == "alive") {
    remote_ipc->send(Message("gladtohearit"), 0);
	started = 1;
    call_out(write_input, 0);
	return;
	}
  else if((<"stderr", "stdout", "error", "result", "complete">)[messages[0]->dta]) {
    if(!msg) { 
	  werror("Got an out of turn message for a request\n");
	  return;
	}
    msg->state = messages[0]->dta;
    msg->data = messages[2]->dta;
    complete_request(msg);
  } else {
     werror("Unknown message %s\n", messages[0]->dta);
  }
}

void read_stdout(mixed id, string data) {
if(current_message)
 ipc->send(({Public.ZeroMQ.Message(current_message->message->header->msg_id), Public.ZeroMQ.Message("stdout"), Public.ZeroMQ.Message(data)}));
}

void read_stderr(mixed id, string data) {
if(current_message)
 ipc->send(({Public.ZeroMQ.Message(current_message->message->header->msg_id), Public.ZeroMQ.Message("stderr"), Public.ZeroMQ.Message(data)}));
}

void queue_request(object message) {
werror("queueing request %O\n", message);
  queue->write((["message": message]));
  write_input();
}

mixed write_input(mixed ... args) {
werror("write_input(%O)\n", args);
  if(!started) {
    werror("haven't started yet.\n");
    return 0;
  }
  if(waiting) {
  	werror("skipping because we're waiting\n");  
	return 0; 
  }
  waiting = 1;
  mixed m = queue->read();
  if(!m|| !objectp(m->message)) { waiting = 0; return 0; }
  else current_message = m;
  string s = current_message->message->content->code;
  werror("writing to hilfe: %O, %O\n", s, current_message);
  remote_ipc->send(({Public.ZeroMQ.Message("evaluate"), Public.ZeroMQ.Message(current_message->message->header->msg_id), 
		 			Public.ZeroMQ.Message(s)}));
}

void complete_request(mixed msg) {
  waiting = 0;
  int count;
  string out;
  string warn;
  mixed err;
  
  werror("DATA: %O\n", msg->data);
  if(msg->state == "result")   {
  err = catch {
  [warn, count, out] = array_sscanf(msg->data, "%s(%d) Result: %s");
  };
 
  if(count && out)
    ipc->send(({Public.ZeroMQ.Message(msg->message->header->msg_id), Public.ZeroMQ.Message("" + count),
		 			Public.ZeroMQ.Message((sizeof(warn)?(warn+"\n"):"") + out)}));
  else
    ipc->send(({Public.ZeroMQ.Message(msg->message->header->msg_id), Public.ZeroMQ.Message("0"), Public.ZeroMQ.Message("")}));
} else {
werror("sending " + msg->state + "\n");

    ipc->send(({Public.ZeroMQ.Message(msg->message->header->msg_id), Public.ZeroMQ.Message(msg->state), Public.ZeroMQ.Message(msg->data)}));
werror("sent " + msg->state + "\n");

}
  if((<"complete", "error">)[msg->state]) {
    current_message = 0;
    call_out(write_input, 0);
  }
	
} 	

  void create_poll_threads() {
    werror("HilfeRunner Starting poller 1\n");
    poll_thread = Thread.Thread(run_poller, poll);
  }

void run_poller(object poller) {
  int rv;
  
  werror("Starting poll thread.\n");
  do {
    rv = poll->poll(1.0);
	//werror("HilfeRunner Poll completed with rv=%d\n", rv);
  } while (rv >= 0 && keep_going);
  
  werror("Poller exiting.\n");
}