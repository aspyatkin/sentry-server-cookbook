name 'sentry-server'
maintainer 'Alexander Pyatkin'
maintainer_email 'aspyatkin@gmail.com'
license 'MIT'
version '0.1.0'
description 'Installs and configures Sentry server'

recipe 'sentry-server::default', 'Installs and configures Sentry server'

source_url 'https://github.com/aspyatkin/sentry-server-cookbook' if respond_to?(:source_url)
depends 'instance', '~> 2.0.0'
depends 'secret', '~> 1.0.0'
depends 'libxslt', '~> 1.0.1'
depends 'libffi', '~> 1.0.1'
depends 'libxml2', '~> 0.1.1'
depends 'poise-python', '~> 1.6.0'
depends 'supervisor', '~> 0.4.12'
depends 'postgresql', '~> 6.1.1'
depends 'database', '~> 6.1.1'
depends 'nginx', '~> 7.0.0'
depends 'tls', '~> 3.0.0'

supports 'ubuntu'
