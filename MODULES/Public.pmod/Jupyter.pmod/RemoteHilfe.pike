
 inherit Tools.KernelHilfe.Evaluator;
 import Public.ZeroMQ;

object infile, outfile;
object myinfile, myoutfile;

object context;
object poll;
object ipc; // inproc pair
Thread.Thread poll_thread;
int keep_going = 1;
int have_announced = 0;
int parent_id;

ADT.Queue queue = ADT.Queue();
object time = System.Time();

int waiting = 0;

  string outbuffer="";
  array res_outbuffer = ({});
  
  mapping current_msg;
  

  string getTime() {
     return replace(ctime(time->sec), "\n", ".") + sprintf("%03d", time->usec/1000);
  }
  
  void print_version() {
  }

  // method that captures output written from hilfe (but not the final results of evaluation)
  void send_output(string s, mixed ... args)
  {
  //werror("send_output(%O, %O)\n", s, args);
    outbuffer+=sprintf(s,@args);
  }

  void stdin_closed(mixed ... args) {
    close_callback();
  }

  void close_callback()
  {
    write("	Terminal closed.\n");
    destruct(this);
	exit(0);
  }

  // let the parent hilfe runner know that we're alive and ready to process requests.
  void announce() {
    if(!have_announced)
	   queue_write(({Message("alive")}));
  	call_out(announce, 0.5);
	//  werror("Announced we're alive\n");
	  
  }

  // write callback for hilferunner-remotehilfe zmq socket
  // currently called manually whenever we want to send, since we will not likely hit the high water mark.
  // see queue_write().
  void ipc_send(object socket) {
     array x = queue->read();
	 if(x) {
	 //werror("%s Sending to kernel: %O\n", getTime(), x);
       int rv = ipc->send(x);
	  // if(rv <0)
      //   werror("Error sending: " + Public.ZeroMQ.errno() + "\n");
      }  
  }
  
  // write messages to the output queue and process the queue. 
  // this is in lieu of using a write callback as using POLLOUT triggers cpu spinning
  void queue_write(array msgs) {
    queue->write(msgs);
	ipc_send(ipc);
  }

  Thread.Mutex mutex = Thread.Mutex();
  // read callback for hilferunner-remotehilfe zmq socket
  void ipc_recv(object socket, mixed ... messages) {
    Thread.MutexKey key = mutex->lock();
	 //werror("%s Received from kernel: %O\n", getTime(), messages);
    //werror("IPC RECV: %O\n", messages);
	if(sizeof(messages) == 1) {
	  if(messages[0]->dta == "gladtohearit") {
	  //werror("Have announced\n");
	  have_announced = 1;
	  key = 0;
	  return;
	  } else {
	    //werror("RemoteHilfe: got unknown message: " + messages[0]->dta + "\n");
		key = 0;
		return;
	  }
	}
	string cmd = messages[0]->dta;
	
  if(cmd == "complete") {
	string s = messages[2]->dta;
    array completions = get_completions(s[0..(int)messages[3]->dta]);
	werror("got completions for %s: %O\n", s[0..(int)messages[3]->dta], completions);
	queue_write( ({ Message("completions"), Message(messages[1]->dta), Message(Standards.JSON.encode(completions)) }));  
	// we've completed processing the block of statements sent to us.
	queue_write( ({ Message("complete"), Message(messages[1]->dta), Message("") }));  
	
  }
  
  else if(cmd == "evaluate") {
	string s = messages[2]->dta;
    foreach(s/"\n";; string line) {
      add_buffer(line);
	}
	
	  if(sizeof(outbuffer))
  	   queue_write(({Message("stdout"), Message(messages[1]->dta), Message(outbuffer)}));  
	  foreach(res_outbuffer;; mixed res)
	    if(stringp(res))
  	      queue_write( ({ Message("result"), Message(messages[1]->dta), Message(res) }));  
	    else
  	      queue_write( ({ Message("result_object"), Message(messages[1]->dta), Message(Standards.JSON.encode(res)) }));  

// version 5.x of jupyter protocol has support for knowing if statement is complete, we may want to use that
// instead of sending an error.
	if(!state->finishedp()) {
  	   queue_write(({Message("error"), Message(messages[1]->dta), Message(sprintf("Incomplete Statement: %s",  
		(((state->get_pipeline()*"")/"\n")-({""})) * "\n"
			))}));
		state->flush();
	}
	else {
	// we've completed processing the block of statements sent to us.
	  call_out(queue_write, 0, ({ Message("complete"), Message(messages[1]->dta), Message("") }));  
	}
	  outbuffer = "";
	  res_outbuffer = ({});
  }
  key = 0;
}
  

 //! The standard @[reswrite] function.
 // rather than writing results to stdout and then scraping them, we 
 // can grab them here and add them to a result buffer. that way,
 // actual output from write() will get collected and sent as stdout.
  void std_reswrite(function w, string sres, int num, mixed res, mixed comp_time, mixed eval_time) {
 // werror("RESWRITE: %O %O, %O, %O	\n", w, sres, num, res, comp_time, eval_time);
    if(!sres)
      res_outbuffer += ({("Ok.\n")});
    else if(objectp(res) && res->to_mime_result) {
	  res_outbuffer += ({res->to_mime_result() + (["execution_count": num])});
	}
    else
      res_outbuffer += ({sprintf( "(%d) Result: %s\n", num,
         replace(sres, "\n", "\n           "+(" "*sizeof(""+num))) )});
  }


  protected void create(int port, int ppid)
  {
    parent_id = ppid;
	
    infile = Stdio.File("stdin");
	infile->set_nonblocking();
	infile->set_close_callback(stdin_closed);
	
    context = Context();
	poll = Poll();
	
    ipc = Socket(context, PAIR);

	//werror("Remote binding on port tcp://localhost:" + port);

    ipc->connect("tcp://localhost:" + port);
    poll->add_socket(ipc, ipc_recv);
    call_out(create_poll_threads, 0);
    call_out(announce, 0.5);
	call_out(check_parent, 5);
    write=send_output;
    ::create();
  }
  
  // when the parent kernel goes away, we should as well.
  void check_parent() {
    if(parent_id != System.getppid()) {
	  werror("RemoteHilfe: parent died, exiting ourselves.\n");
	  exit(0);
	}
    call_out(check_parent, 5);
  }
  
  void create_poll_threads() {
    poll_thread = Thread.Thread(run_poller, poll);
  }

void run_poller(object poller) {
  int rv;
  
  do {
    rv = poll->poll(1.0);
//	sleep(1.0);
  } while (rv >= 0 && keep_going);
  
  werror("RemoteHilfe Poller exiting.\n");
}