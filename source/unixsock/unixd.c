/*
 * Simple UNIX domain socket server
 */
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <stdlib.h>
#include <stdio.h>
#include <signal.h>
#include <sys/wait.h>
#include <string.h>

char *dftcmd[] = {
  "/bin/sh",
  "-l",
  NULL,
};

void reaper(int signo) {
  int status;
  pid_t pid;

  while ((pid = waitpid(-1, &status, WNOHANG)) > 0) ;
}
    
int main(int argc,char *argv[]) {
  struct sockaddr_un addr;
  int srv, cln;
  char *socket_path, **cmd;
  pid_t cpid;

  //~ fprintf(stderr,"STARTING (%s,%d)\n",__FILE__,__LINE__);
  if (argc < 2) {
    fprintf(stderr, "Usage:\n\t%s socket-path [cmd args]\n", argv[0]);
    exit(2);
  } else if (argc == 2) {
    cmd = dftcmd;
  } else {
    cmd = argv+2;
  }
  socket_path = argv[1];

  if ((srv = socket(AF_UNIX,SOCK_STREAM,0)) == -1) {
    perror("socket");
    exit(3);

  }
  
  memset(&addr,0,sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path)-1);
  unlink(socket_path);

  if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
    perror(socket_path);
    exit(4);
  }
  if (listen(srv,5) == -1) {
    perror("listen");
    exit(5);
  }
  signal(SIGCHLD,reaper);
  //~ fprintf(stderr,"READY (%s,%d)\n",__FILE__,__LINE__);

  for (;;) {
    if ((cln = accept(srv,NULL,NULL)) == -1) {
      perror("accept");
      continue;
    }
    //~ fprintf(stderr,"ACCEPT (%s,%d)\n",__FILE__,__LINE__);
    cpid = fork();
    switch (cpid) {
    case -1:
      perror("fork");
      close(cln);
      continue;
    case 0:
      close(srv);
      dup2(cln,fileno(stdin));
      dup2(cln,fileno(stdout));
      dup2(cln,fileno(stderr));
      //~ fprintf(stderr,"EXEC %s(%d) (%s,%d)\n",cmd[0],getpid(),__FILE__,__LINE__);
      execvp(cmd[0],cmd);
      perror("exec");
      exit(7);
    default:
      //~ fprintf(stderr,"MAIN (%s,%d)\n",cmd[0],__FILE__,__LINE__);
      close(cln);
    }
  }
}
    
  
  
