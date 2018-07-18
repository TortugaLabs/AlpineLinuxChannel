/*
 * Basic UNIX domain socket client
 */
#include <sys/socket.h>
#include <sys/un.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>

void pump(int ifd,int ofd,pid_t peer) {
  int cnt, rc;
  char buf[4096];

  while ((cnt = read(ifd, buf, sizeof(buf))) > 0) {
    if ((rc = write(ofd, buf, cnt)) != cnt) {
      if (rc > 0) {
	fputs("partial write\n",stderr);
      } else {
	perror("write");
	break;
      }
    }
  }
  kill(peer,SIGTERM);
}
	

int main(int argc,char *argv[]) {
  struct sockaddr_un addr;
  int sock;
  pid_t pid;

  if (argc != 2) {
    fprintf(stderr,"Usage:\n\t%s socket-path\n", argv[0]);
    exit(1);
  }

  if ((sock=socket(AF_UNIX,SOCK_STREAM,0)) == -1) {
    perror("socket");
    exit(2);
  }
  memset(&addr,0,sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, argv[1], sizeof(addr.sun_path)-1);

  if (connect(sock,(struct sockaddr *)&addr,sizeof(addr)) == -1) {
    perror(argv[1]);
    exit(3);
  }

  pid = fork();
  switch (pid) {
  case -1:
    perror("fork");
    exit(4);
  case 0:
    pump(fileno(stdin),sock,getppid());
    break;
  default:
    pump(sock,fileno(stdout),pid);
    break;
  }
}
  
