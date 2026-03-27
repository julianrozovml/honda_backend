<?php
/**
 * honda-motoverso — settings.php
 * Sin credenciales — todo viene de settings.local.php
 * que el entrypoint.sh genera desde variables de entorno.
 */
if (file_exists($app_root . '/' . $site_path . '/services.yml')) {
  $settings['container_yamls'][] = $app_root . '/' . $site_path . '/services.yml';
}
if (file_exists($app_root . '/' . $site_path . '/settings.local.php')) {
  include $app_root . '/' . $site_path . '/settings.local.php';
}
