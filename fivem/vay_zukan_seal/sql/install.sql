CREATE TABLE IF NOT EXISTS `vay_zukan_seal` (
  `citizenid` VARCHAR(50) NOT NULL,
  `owned` LONGTEXT NOT NULL,
  `claimed` LONGTEXT NOT NULL,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
