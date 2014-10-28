require boxen::environment
require homebrew
require gcc

Exec {
  group       => 'staff',
  logoutput   => on_failure,
  user        => $boxen_user,

  path => [
    "${boxen::config::home}/rbenv/shims",
    "${boxen::config::home}/rbenv/bin",
    "${boxen::config::home}/rbenv/plugins/ruby-build/bin",
    "${boxen::config::home}/homebrew/bin",
    '/usr/bin',
    '/bin',
    '/usr/sbin',
    '/sbin'
  ],

  environment => [
    "HOMEBREW_CACHE=${homebrew::config::cachedir}",
    "HOME=/Users/${::boxen_user}"
  ]
}

File {
  group => 'staff',
  owner => $boxen_user
}

Package {
  provider => homebrew,
  require  => Class['homebrew']
}

Repository {
  provider => git,
  extra    => [
    '--recurse-submodules'
  ],
  require  => File["${boxen::config::bindir}/boxen-git-credential"],
  config   => {
    'credential.helper' => "${boxen::config::bindir}/boxen-git-credential"
  }
}

Service {
  provider => ghlaunchd
}

Homebrew::Formula <| |> -> Package <| |>

node default {
  # core modules, needed for most things
  include dnsmasq
  include git
  include hub
  include nginx
  include brewcask

  # Disabled for now because of issues with FileVault and Yosemite (hang on reboot)
  # fail if FDE is not enabled
  # if $::root_encrypted == 'no' {
  #  fail('Please enable full disk encryption and try again')
  #}

  # node versions
  #include nodejs::v0_6
  #include nodejs::v0_8
  include nodejs::v0_10

  # default ruby versions
  #ruby::version { '1.9.3': }
  #ruby::version { '2.0.0': }
  #ruby::version { '2.1.0': }
  #ruby::version { '2.1.1': }

  # Set our new Ruby version
  # NOTE: You can also specify versions to install as shown a few lines above
  # See the Puppet-ruby module on Github for more info:
  #  https://github.com/boxen/puppet-ruby

  $ruby_version = '2.1.2'
  ruby::version { $ruby_version: }

  # This sets our default in rbenv
  class { 'ruby::global':
    version => $ruby_version
  }

  ruby_gem { 'bundler for all rubies':
    gem          => 'bundler',
    version      => '~> 1.0',
    ruby_version => '*',
  }

  ruby_gem { "puppet-lint for ${ruby_version}":
    gem          => 'puppet-lint',
    version      => '~> 1.0.1',
    ruby_version => $ruby_version,
  }
  ruby_gem { "puppet-syntax for ${ruby_version}":
    gem          => 'puppet-syntax',
    version      => '~> 1.3.0',
    ruby_version => $ruby_version,
  }

  # puppet-ruby breaks some gems, this is my silly work around..
  exec { "bundle config charlock_holmes for ${ruby_version}":
    command => "bundle config build.charlock_holmes --with-icu-dir=${boxen::config::homebrewdir}/opt/icu4c",
    onlyif  => 'bundle config build.charlock_holmes | grep -q "You have not"',
  }

  exec { "charlock_holmes for ${ruby_version}":
    command => "env -i zsh -c 'source /opt/boxen/env.sh && RBENV_VERSION=${ruby_version} gem install charlock_holmes'",
    unless  => "env -i zsh -c 'source /opt/boxen/env.sh && RBENV_VERSION=${ruby_version} gem list charlock_holmes | grep charlock_holmes'",
    require => Exec["bundle config charlock_holmes for ${ruby_version}"],
  }

  exec { "bundle config nokogiri for ${ruby_version}":
    command => "bundle config build.nokogiri --use-system-libraries --with-xml2-include=${boxen::config::homebrewdir}/opt/libxml2/include/libxml2",
    onlyif  => 'bundle config build.nokogiri | grep -q "You have not"',
  }

  exec { "nokogiri for ${ruby_version}":
    command => "env -i zsh -c 'source /opt/boxen/env.sh && RBENV_VERSION=${ruby_version} gem install nokogiri -- --with-iconv-lib=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX${::macosx_productversion_major}.sdk/usr/lib --with-iconv-include=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX${::macosx_productversion_major}.sdk/usr/include'",
    unless  => "env -i zsh -c 'source /opt/boxen/env.sh && RBENV_VERSION=${ruby_version} gem list nokogiri | grep nokogiri'",
    require => [
      Package['libxml2'],
      Exec["bundle config nokogiri for ${ruby_version}"],
    ],
  }

  # Gollum requires some stuff first..
  ruby_gem { "gollum for ${ruby_version}":
    gem          => 'gollum',
    version      => '~> 3.0.0',
    ruby_version => $ruby_version,
    require      => [
      Package['icu4c'],
      Exec["charlock_holmes for ${ruby_version}"],
      Exec["nokogiri for ${ruby_version}"],
    ],
  }

  # common, useful packages via Homebrew
  $brew_packages = [
      'ack',
      'icu4c',
      'findutils',
      'coreutils',
      'libxml2',
      'keychain',
      'go',
      'htop-osx',
      'jq',
      'multimarkdown',
      'nmap',
      'mercurial',
      'lynx',
      'gnu-tar'
  ]

  # Install the above packages using the default provider which is homebrew
  package { $brew_packages: }

  $brewcask_packages = [
    'iterm2',
    'mou',
    'chicken'
  ]

  package { $brewcask_packages:
    provider => 'brewcask',
  }

  file { "${boxen::config::srcdir}/our-boxen":
    ensure => link,
    target => $boxen::config::repodir
  }
}
