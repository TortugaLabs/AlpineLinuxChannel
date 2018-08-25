/*
 * Basic UNIX domain socket client
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>
#include <fcntl.h> 

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
  int fd;
  pid_t pid;

  if (argc != 2) {
    fprintf(stderr,"Usage:\n\t%s tty-path\n", argv[0]);
    exit(1);
  }

  if ((fd = open(argv[1],O_RDWR|O_NOCTTY|O_SYNC)) == -1) {
    perror(argv[1]);
    exit(1);
  }
  
  pid = fork();
  switch (pid) {
  case -1:
    perror("fork");
    exit(4);
  case 0:
    pump(fileno(stdin),fd,getppid());
    break;
  default:
    pump(fd,fileno(stdout),pid);
    break;
  }
}
  
