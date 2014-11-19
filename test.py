#!/usr/bin/python
import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('perfhub-wdc',username='gopakumarr',password='Thomas2007')
stdin,stdout,stderr  = ssh.exec_command('./deploy-visor-pxe.sh -s /perfauto/builds/visor/prod2013-stage/release/24xxxxx/visor-pxe-2403389.tgz -d /mts/home3/gopakumarr/nehicurrentCS -k -r /mts/home3/gopakumarr/devel-postboot-sh -v')
#DIR = "nehicurrentCS"
#stdin,stdout,stderr  = ssh.exec_command('ls %s' % DIR)
print stdout.readlines()
