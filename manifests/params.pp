# @summary Default parameters for the Apt module.
class apt::params {
  $root = '/etc/apt'
  $sources_list_d = "${root}/sources.list.d"
  $conf_d = "${root}/apt.conf.d"
  $preferences_d = "${root}/preferences.d"

  $config_files = {
    'conf'    => {
      'path' => $conf_d,
      'ext'  => '',
    },
    'pref'    => {
      'path' => $preferences_d,
      'ext'  => '.pref',
    },
    'list'    => {
      'path' => $sources_list_d,
      'ext'  => '.list',
    },
    'sources' => {
      'path' => $sources_list_d,
      'ext'  => '.sources',
    },
  }
}
