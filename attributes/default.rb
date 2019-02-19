id = 'sentry-server'

default[id]['fqdn'] = nil
default[id]['version'] = '9.0.0'

default[id]['security']['ssl'] = false
default[id]['security']['use_ec_certificate'] = false
default[id]['security']['hsts_max_age'] = 15_768_000
default[id]['security']['hpkp_max_age'] = 604_800

default[id]['config']['web']['workers'] = 3
default[id]['config']['worker']['processes'] = 4
default[id]['config']['max_stacktrace_frames'] = 500
default[id]['config']['admin_email'] = ''

default[id]['config']['entities'] = {}

default[id]['cleanup']['enabled'] = false
default[id]['cleanup']['days'] = 30
default[id]['cleanup']['cron']['mailto'] = nil
default[id]['cleanup']['cron']['mailfrom'] = nil
default[id]['cleanup']['cron']['minute'] = '0'
default[id]['cleanup']['cron']['hour'] = '*/12'
default[id]['cleanup']['cron']['day'] = '*'
default[id]['cleanup']['cron']['month'] = '*'
default[id]['cleanup']['cron']['weekday'] = '*'

default[id]['backup']['enabled'] = false
default[id]['backup']['aws']['iam']['account_alias'] = 'backup_user'
default[id]['backup']['aws']['s3']['bucket_region'] = nil
default[id]['backup']['aws']['s3']['bucket_name'] = nil
default[id]['backup']['cron']['mailto'] = nil
default[id]['backup']['cron']['mailfrom'] = nil
default[id]['backup']['cron']['minute'] = '0'
default[id]['backup']['cron']['hour'] = '2'
default[id]['backup']['cron']['day'] = '*'
default[id]['backup']['cron']['month'] = '*'
default[id]['backup']['cron']['weekday'] = '*'
