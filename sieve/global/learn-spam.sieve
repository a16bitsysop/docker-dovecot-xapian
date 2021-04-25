require ["vnd.dovecot.pipe", "copy", "imapsieve"];
pipe :copy "curl" ["--data-binary", "@-", "http://localhost:11334/learnspam" ];

