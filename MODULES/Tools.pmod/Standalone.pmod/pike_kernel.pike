
#pike __REAL_VERSION__

constant description = "Jupyter kernel for pike.";

class Options
{
  inherit Arg.Options;

  constant help_pre = #"Usage: pike-kernel [-f configfile] [-r port]
";

  constant file_help = "Jupyter kernel config file to use.";
  constant remote_help = "Remote IPC port to use.";

  Opt file = HasOpt("-f");
  Opt remote = HasOpt("-r");
}

object kernel;
object remote;

int main(int argc, array(string) argv)
{
  object opts = Options(argv);
  
  mapping config;
  
  if(opts->file) {
    if(!file_stat(opts->file)) {
	  werror("Configuration file %s does not exist.\n", opts->file);
	  exit(1);
	}
    config = Standards.JSON.decode(Stdio.read_file(opts->file));
  } else if(opts->remote) {
     if(!(int)opts->remote) {
	   werror("Report port %d must be an integer.\n", opts->remote);
	   exit(2);
	 }
  }else {
    werror("No configuration file provided.\n");
    exit(1);
  }
  
  if(config)
    kernel = Public.Jupyter.Kernel(config);
  else 
    remote = Public.Jupyter.RemoteHilfe((int)opts->remote);

  return -1;
}
