ALTER TABLE `session` ADD `login_method` text
  CONSTRAINT `ck_session_login_method`
  CHECK (`login_method` IS NULL OR `login_method` IN ('email', 'google', 'apple'));
