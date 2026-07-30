CREATE TABLE IF NOT EXISTS `vulfayne_collectibles` (
  `citizenid` VARCHAR(50) NOT NULL,
  `category` VARCHAR(20) NOT NULL,
  `owned` LONGTEXT NOT NULL,
  `claimed` LONGTEXT NOT NULL,
  PRIMARY KEY (`citizenid`, `category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
