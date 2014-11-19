#!/usr/bin/python
import paramiko
import commands
from scp import SCPClient

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('w1-parm-wesd',username='root',password='')
stdin, stdout, stderr = ssh.exec_command('ls /vmfs/volumes/datastore1/playground/benchdata | grep -v run')
TEST = stdout.readlines()
scp = SCPClient(ssh.get_transport())
fh = open('test','w')
for i in xrange(int(len(TEST))):
	scp.get('/vmfs/volumes/datastore1/playground/benchdata/%s' % TEST[i].strip())
	output = commands.getoutput('/usr/bin/perl get-scores.pl -i %s -n %s -b -a' % (TEST[i].strip(),TEST[i].strip()))
	fh.write(output)
	fh.write("\n")
fh.close()

	




