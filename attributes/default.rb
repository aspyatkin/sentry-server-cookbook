id = 'sentry-server'

default[id]['fqdn'] = nil

default[id]['security']['ssl'] = false
default[id]['security']['use_ec_certificate'] = false
default[id]['security']['hsts_max_age'] = 15_768_000
default[id]['security']['hpkp_max_age'] = 604_800

default[id]['config']['web']['workers'] = 3
default[id]['config']['worker']['processes'] = 4
default[id]['config']['max_stacktrace_frames'] = 500
default[id]['config']['admin_email'] = ''

default[id]['config']['entities'] = {}
