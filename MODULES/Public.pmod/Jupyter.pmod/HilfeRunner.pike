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

object time = System.Time();

  string getTime() {
     return replace(ctime(time->sec), "\n", ".") + sprintf("%03d", time->usec/1000);
  }

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
  poll->add_socket(remote_ipc, ipc_recv);
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

//Thread.Mutex ipc_mutex = Thread.Mutex();

void ipc_recv(object socket, mixed ... messages) {
  Thread.MutexKey key = mutex->lock();
  mixed msg = ([]);
  werror("%s IPC: %O\n", getTime(), messages);
/*
  if(sizeof(messages) > 1 && (!msg || messages[1]->dta != msg->message->header->msg_id)) {
    werror("WARNING: Received a message from RemoteHilfe for different request: got %s expected %s\n", messages[1]->dta, (msg?msg->message->header->msg_id:"no message"));
  }
  */
  if(messages[0]->dta == "alive") {
    remote_ipc->send(Message("gladtohearit"), 0);
	started = 1;
    call_out(write_input, 0);
	key = 0;
	return;
	}
  else if((<"stderr", "stdout", "error", "result",  "result_object", "complete", "completions">)[messages[0]->dta]) {
    if(!msg) { 
	  werror("Got an out of turn message for a request\n");
	  key = 0;
	  return;
	}
    msg->state = messages[0]->dta;
	msg->request_id = messages[1]->dta;
    msg->data = messages[2]->dta;
    complete_request(msg);
  } else {
     werror("Unknown message %s\n", messages[0]->dta);
  }
  key = 0;
}

void read_stdout(mixed id, string data) {
 object key = mutex->lock();
 send_stdout(data); 
 key = 0;
}

void send_stdout(string data) {
  if(current_message)
     ipc->send(({Public.ZeroMQ.Message(current_message->message->header->msg_id), Public.ZeroMQ.Message("stdout"), Public.ZeroMQ.Message(data)}));
}

void read_stderr(mixed id, string data) {
  object key = mutex->lock();
  send_stderr(data);
 key = 0;
}

void send_stderr(string data) {
  if(current_message)
    ipc->send(({Public.ZeroMQ.Message(current_message->message->header->msg_id), Public.ZeroMQ.Message("stderr"),    Public.ZeroMQ.Message(data)}));
}

void queue_request(object message) {
werror("%s queueing request %O\n", getTime(), message);
  queue->write((["message": message]));
  write_input();
}

Thread.Mutex mutex = Thread.Mutex();

mixed write_input(mixed ... args) {
  Thread.MutexKey key = mutex->lock();
  if(waiting) {
  	werror("skipping because we're waiting: %O\n", current_message);  
	key = 0;
	return 0; 
  }
  if(!started) {
    werror("haven't started yet.\n");
	key = 0;
    return 0;
  }
  waiting = 1;
  werror("write_input(%O)\n", args);
  mixed m = queue->read();
  if(!m|| !objectp(m->message)) { waiting = 0; return 0; }
  else current_message = m;

  string request_type;
  if(current_message->message->message_type == "complete_request") 
    request_type = "complete";
  else 
    request_type = "evaluate";

werror("message content: %O\n", current_message->message->content);		
  string s = current_message->message->content->code || current_message->message->content->line;
  werror("writing to hilfe: %O, %O\n", s, current_message);
  
  array messages = ({Public.ZeroMQ.Message(request_type), Public.ZeroMQ.Message(current_message->message->header->msg_id), 
		 			Public.ZeroMQ.Message(s)});
					
werror("%s writing:", getTime());
werror("%O\n", messages);
  if(request_type == "complete") {
    string pos = current_message->message->content->cursor_pos + "";
	werror("pos: %O\n", pos);
    messages += ({Public.ZeroMQ.Message(pos)});
  }
  remote_ipc->send(messages);
  werror("%s wrote to hilfe: %O, %O\n", getTime(), s, current_message);
  key = 0;
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
    ipc->send(({Public.ZeroMQ.Message(msg->request_id), Public.ZeroMQ.Message("" + count),
		 			Public.ZeroMQ.Message((sizeof(warn)?(warn+"\n"):"") + out)}));
  else
    ipc->send(({Public.ZeroMQ.Message(msg->request_id), Public.ZeroMQ.Message("0"), Public.ZeroMQ.Message("")}));
} else {
  werror("sending " + msg->state + "\n");

  // make sure that we send any stdout or stderr before we mark the request complete.
  if((<"complete", "error">)[msg->state]) {
    try_read_data();
  }

    ipc->send(({Public.ZeroMQ.Message(msg->request_id), Public.ZeroMQ.Message(msg->state), Public.ZeroMQ.Message(msg->data)}));
  werror("sent " + msg->state + "\n");

  }
  if((<"complete", "error">)[msg->state]) {
    current_message = 0;
    waiting = 0;
    call_out(write_input, 0);
  }
} 	

  void try_read_data() {
  myoutfile->set_blocking_keep_callbacks();
  string so = "";
  string s;
  do {
    s = 0;
    if(myoutfile->peek(0.01))
      s = myoutfile->read(1024, 1);
	if(s) so += s;
  } while(s);
      
  if(sizeof(so)) send_stdout(so);
  
  myoutfile->set_nonblocking();
  
  myerrfile->set_blocking_keep_callbacks();
  string se = "";
  do {
    s = 0;
    if(myerrfile->peek(0.01))
      s = myerrfile->read(1024, 1);
	if(s) se += s;
  } while(s);
      
  if(sizeof(se)) send_stderr(se);
  
  myerrfile->set_nonblocking();  
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