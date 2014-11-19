#!/usr/bin/python
import paramiko
import subprocess
import time
import os
import commands
from scp import SCPClient

lf = open("/root/rahul/launcher_environment/Launcher/Trigger","rb")
trig_paras = lf.read()
values = []
for i in trig_paras.split() :
	values.append(i)

if len(values) < 4 :
	print "There is something missing in your life"
else :
	#Runlist = values[3]
        
	#print "No runlist"
	Machine = values[0]
	Branch = values[1]
	Change = values[2]
	Runlist = values[3]
	print "Machine : %s" % Machine
	print "Branch : %s" % Branch
	print "Change : %s" % Change
	print "Runlist : %s" % Runlist
	
	if Machine == "w1-pamo-nehl" :
		MAC = "90:b1:1c:1f:0e:8c"
		print MAC
	if Machine == "w1-pamo-nehi" :
		MAC = "d4:85:64:4a:a5:2c"
	if Machine == "w1-pamo-abub" :
		MAC = "d4:ae:52:e9:13:90"
	if Machine == "w1-parm-wesd" :
		MAC = "6c:3b:e5:a5:c0:08"

	print "#### Deploying build ####"
	HOST = "gopakumarr@perfhub-wdc"
	#deploy = subprocess.call(['ssh',HOST,'cat','mac'])
	sub_deploy_dir = int(Change) / 100000
	Sub_Deploy_Dir = "%sxxxxx" % sub_deploy_dir
	ssh = paramiko.SSHClient()
	ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
	ssh.connect('perfhub-wdc',username='gopakumarr',password='Thomas2007')
	stdin,stdout,stderr  = ssh.exec_command('./deploy-visor-pxe.sh -s /perfauto/builds/visor/%s/release/%s/visor-pxe-%s.tgz -d /mts/home3/gopakumarr/Trigger_Pxe_Dir -k -r /mts/home3/gopakumarr/devel-postboot-sh -v' % (Branch,Sub_Deploy_Dir,Change))
	print stdout.readlines()
	print stderr.readlines()
	stdin,stdout,stderr  = ssh.exec_command('sudo -u performance ssh pxeuser@suite ./PXEconfig.pl -m %s -p /mts/home3/gopakumarr/Trigger_Pxe_Dir -l WDC' % MAC)
	#print stdout.readlines()
	#print stderr.readlines()
	print "#### Deploying build and PXE direction completed####"
	ssh.close()

	ssh_run_boot = paramiko.SSHClient()
	ssh_run_boot.set_missing_host_key_policy(paramiko.AutoAddPolicy())
	ssh_run_boot.connect('%s' % Machine,username='root',password='') 
        stdin,stdout,stderr  = ssh_run_boot.exec_command('reboot')
	ssh_run_boot.close()
	time.sleep(300)
	ssh_status = 1
	TESTBED = "root@%s" % Machine
	while ssh_status > 0 :
		ssh_status,output = commands.getstatusoutput("ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa_launcher %s 'date'" % TESTBED)
		print "Machine is Down"
		time.sleep(2)
	print "Testbed booted up"	
	ssh_run_test = paramiko.SSHClient()
	ssh_run_test.set_missing_host_key_policy(paramiko.AutoAddPolicy())
 	ssh_run_test.connect('%s' % Machine,username='root',password='')
	channel = ssh_run_test.invoke_shell()
	stdin = channel.makefile('wb')
	stdout = channel.makefile('rb')
	print "Test started with Runlist %s" % Runlist	
	stdin.write('''
	cd /vmfs/volumes/datastore1/playground
	./pxebench.sh %s
	exit
	''' % Runlist)
	#print "Test Completed"
	print stdout.read()
	stdout.close()
	stdin.close()
	ssh_run_test.close()
	
	ssh_get_test_name = paramiko.SSHClient()
	ssh_get_test_name.set_missing_host_key_policy(paramiko.AutoAddPolicy())
	ssh_get_test_name.connect('%s' % Machine,username='root',password='')
	stdin, stdout, stderr = ssh_get_test_name.exec_command('ls /vmfs/volumes/datastore1/playground/benchdata | grep -v run')
	print "Copied Results Directory"
	TEST = stdout.readlines()
	for i in xrange(int(len(TEST))):
		print TEST[i].strip()
	ssh_get_test_name.close()
	ssh_scp = paramiko.SSHClient()
	ssh_scp.set_missing_host_key_policy(paramiko.AutoAddPolicy())
	ssh_scp.connect('%s' % Machine,username='root',password='')
	scp = SCPClient(ssh_scp.get_transport())
	fh = open('results.log','w')
	launcher_details = commands.getoutput('cat launcher_environment/Launcher/Trigger')
	fh.write(launcher_details)
	fh.write("\n")
	for i in xrange(int(len(TEST))):
		scp.get('/vmfs/volumes/datastore1/playground/benchdata/%s' % TEST[i].strip())
		output = commands.getoutput('/usr/bin/perl /root/rahul/Trigger/get-scores.pl -i %s -n %s -b -a' % (TEST[i].strip(),TEST[i].strip()))
		os.system('mv %s %s.rm-tag' % (TEST[i].strip(),TEST[i].strip()))
		fh.write(output)
		fh.write("\n")
	print output
	fh.close()
	print "Emailing Results to Users"
	os.system("/usr/bin/mutt -s 'Result' gopakumarr@vmware.com sarumugam@vmware.com -a /root/rahul/results.log < /dev/null")
	os.system("rm -f `ls | grep 'rm-tag'`")
