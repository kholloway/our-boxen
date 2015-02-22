# OS X specific settings
# See: https://github.com/boxen/puppet-osx
# for information about each setting
class people::kholloway::osx {
  # Keyboard related
  include osx::global::enable_keyboard_control_access
  include osx::global::disable_key_press_and_hold
  include osx::global::enable_standard_function_keys
  include osx::global::disable_autocorrect
  include osx::global::tap_to_click

  class { 'osx::global::key_repeat_delay':
    delay => 5
  }
  # Default here is 0, change this to the statement above to set a different value
  include osx::global::key_repeat_rate

  # Dock
  include osx::dock::autohide

  # Finder settings
  include osx::finder::show_external_hard_drives_on_desktop
  include osx::finder::show_removable_media_on_desktop
  include osx::global::expand_save_dialog
  include osx::no_network_dsstores

  # Misc
  include osx::global::disable_remote_control_ir_receiver

}
