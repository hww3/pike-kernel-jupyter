
 inherit Tools.Hilfe.Evaluator;
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

int waiting = 0;

  string outbuffer="";
  array res_outbuffer = ({});
  
  mapping current_msg;
  
  void print_version() {
  }

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

  void announce() {
    if(!have_announced)
	   queue_write(({Message("alive")}));
  	call_out(announce, 0.5);
	//  werror("Announced we're alive\n");
	  
  }

  void ipc_send(object socket) {
     array x = queue->read();
	 if(x) {
       int rv = ipc->send(x);
	  // if(rv <0)
      //   werror("Error sending: " + Public.ZeroMQ.errno() + "\n");
      }  
  }
  
  void queue_write(array msgs) {
    queue->write(msgs);
	ipc_send(ipc);
  }

  void ipc_recv(object socket, mixed ... messages) {
    //werror("IPC RECV: %O\n", messages);
	if(sizeof(messages) == 1) {
	  if(messages[0]->dta == "gladtohearit") {
	  //werror("Have announced\n");
	  have_announced = 1;
	  return;
	  } else {
	    //werror("RemoteHilfe: got unknown message: " + messages[0]->dta + "\n");
		return;
	  }
	}
	string cmd = messages[1]->dta;
//	if(cmd != "evaluate") werror("Invalid command received.\n");
	string s = messages[2]->dta;
    foreach(s/"\n";; string line) {
      add_buffer(line);
	}
	
//	  queue_write(({ Message("error"), Message(messages[1]->dta), Message(sprintf("Incomplete Statement: %s",  
//		(((state->get_pipeline()*"")/"\n")-({""})) * "\n"
//			))}));
	  if(sizeof(outbuffer))
  	   queue_write(({Message("stdout"), Message(messages[1]->dta), Message(outbuffer)}));  
	  foreach(res_outbuffer;; string res)
 	    queue_write( ({ Message("result"), Message(messages[1]->dta), Message(res) }));  

	if(!state->finishedp()) {
  	   queue_write(({Message("error"), Message(messages[1]->dta), Message(sprintf("Incomplete Statement: %s",  
		(((state->get_pipeline()*"")/"\n")-({""})) * "\n"
			))}));
		state->flush();
	}
	else {
	  queue_write( ({ Message("complete"), Message(messages[1]->dta), Message("") }));  
	}
	  outbuffer = "";
	  res_outbuffer = ({});
  }


 //! The standard @[reswrite] function.
  void std_reswrite(function w, string sres, int num, mixed res) {
 // werror("RESWRITE: %O %O, %O, %O	\n", w, sres, num, res);
    if(!sres)
      res_outbuffer += ({("Ok.\n")});
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
  
  void check_parent() {
    if(parent_id != System.getppid()) {
	  werror("RemoteHilfe: parent died, exiting ourselves.\n");
	  exit(0);
	}
    call_out(check_parent, 5);
  }
  
  void create_poll_threads() {
    //werror("Remote Starting poller 1\n");
    poll_thread = Thread.Thread(run_poller, poll);
  }

void run_poller(object poller) {
  int rv;
  
  //werror("Remote Starting poll thread.\n");
  do {
    rv = poll->poll(1.0);
	sleep(1.0);
//	werror("Remote Poll completed with rv=%d\n", rv);
  } while (rv >= 0 && keep_going);
  
  //werror("RemoteHilfeemote Poller exiting.\n");
}