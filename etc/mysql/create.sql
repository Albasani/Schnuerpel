#
# $Id: create.sql 458 2011-02-16 20:40:46Z alba $
#

DROP TABLE IF EXISTS r_control_setup;
create table r_control_setup
(
  id	INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  name	VARCHAR(16) NOT NULL
);
INSERT INTO r_control_setup(name) VALUES
(''),
('cancel'),
('rmgroup'),
('newgroup'),
('checkgroups');

######################################################################
# This table is an archive of posts sent by our users. Historic
# names and numbers are kept even when account is renamed or deleted.
# Thus no foreign keys to actual accounts.
#
# delete from r_local_post;
DROP TABLE IF EXISTS r_local_post;
create table r_local_post
(
  id BIGINT PRIMARY KEY AUTO_INCREMENT,

  # Contents of field Date:, seconds since epoch
  timestamp INT UNSIGNED NOT NULL,

  # Copy of r_user(username)
  username VARCHAR(128) NOT NULL,

  # Copy of r_user(id)
  userid INT UNSIGNED NOT NULL,

  # Core contents of Message-ID:, i.e. id without surrounding angle
  # brackets. Length according to draft-ietf-usefor-usefor-12
  h_message_id VARCHAR(250) NOT NULL,

  # Contents of header "From:"
  h_from VARCHAR(128) NOT NULL,

  # Contents of header "Control:"
  h_control INT UNSIGNED DEFAULT 0 NOT NULL
	REFERENCES r_control_setup(id),

  # Contents of header "Path:", but only preloaded part
  h_path VARCHAR(64),

  # CancelKey matching server generated CancelLock 
  # but only core, i.e. without prefixing "sha1:"
  h_cancel_key VARCHAR(28) DEFAULT '' NOT NULL,

  # The timestamp index is not unique. It is perfectly legal to post more
  # than one message per second.
  KEY( timestamp ),

  # The Message-ID index is not unique. Submissions to moderated groups
  # are sent by mail, but also recorded in this table. If the moderator
  # uses the same news server to inject the approved posts, they end up
  # in this table twice.
  KEY( h_message_id )
);

-- alter table r_local_post add key(timestamp);
-- alter table r_local_post add key(h_message_id);

######################################################################
DROP TABLE IF EXISTS r_local_post_group;
create table r_local_post_group
(
  id BIGINT NOT NULL
  	REFERENCES r_local_post(id),
  -- Groups in the Newsgroups are counted from left to right, starting
  -- with 1, with an increment of +1
  -- Groups in the Followup-To header are counted from left to right,
  -- starting with -1, with an increment of -1
  group_nr INT DEFAULT 1 NOT NULL,
  group_name VARCHAR(128) NOT NULL,

  # Index is not unique because h_message_id is not unique.
  KEY( id )
);

-- alter table r_local_post_group add key(id);

######################################################################
# Note that MySQL does not use indexes with joins on a views.
# If performance is required use "GROUP BY" instead.
# drop view r_local_post_group_str;
create view r_local_post_group_str as
SELECT id post_id, GROUP_CONCAT( group_name ORDER BY group_nr SEPARATOR ',') post_groups
FROM r_local_post_group
WHERE group_nr > 0
GROUP BY id;

create table r_filter_type
(
  id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  name  VARCHAR(16) NOT NULL
);
INSERT INTO r_filter_type(id, name) VALUES
(1, 'N/A'),
(2, 'spam');

-- drop table r_filtered_posting;
create table r_filtered_posting
(
  # Core contents of Message-ID:, i.e. id without surrounding angle
  # brackets. Length according to draft-ietf-usefor-usefor-12
  id VARCHAR(250) PRIMARY KEY,

  # Contents of field Date:, seconds since epoch
  date INT UNSIGNED NOT NULL,

  filter_type INT UNSIGNED DEFAULT 1 NOT NULL
	REFERENCES r_filter_type(id),

  # 0 = original score,
  # 1 = direct reply to level 0,
  # 2 = direct reply to level 1, etc.
  generation INT UNSIGNED DEFAULT 1 NOT NULL
);

-- drop table r_filtered_reference;
create table r_filtered_reference
(
  id VARCHAR(250) NOT NULL
	REFERENCES r_filtered_posting(id),
  reference VARCHAR(250) NOT NULL,
  INDEX(reference)
);

create table r_lang_setup
(
  id CHAR(2) NOT NULL,
  name VARCHAR(15) NOT NULL,
  PRIMARY KEY(id)
);
INSERT INTO r_lang_setup(id, name)
VALUES ('en', 'English'), ('de', 'Deutsch');

create table r_sex_setup
(
  id CHAR(1) NOT NULL,
  name VARCHAR(15) NOT NULL,
  PRIMARY KEY(id)
);
INSERT INTO r_lang_setup(id, name)
VALUES ('-', 'N/A'), ('f', 'Female'), ('m', 'Male');

create table r_status_setup
(
  id CHAR(1) NOT NULL,
  name VARCHAR(15) NOT NULL,
  PRIMARY KEY(id)
);
INSERT INTO r_status_setup(id, name)
VALUES (1, 'active'), (2, 'signed off'), (3, 'closed');

create table r_user
(
  id		INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  created	INT UNSIGNED NOT NULL,
  last_login	INT UNSIGNED,
  last_host	VARCHAR(64),
  status	CHAR(1) DEFAULT 1 NOT NULL REFERENCES r_status_setup(id),
  username	VARCHAR(128) NOT NULL UNIQUE,
  first_name	VARCHAR(128),
  last_name	VARCHAR(128),
  email		VARCHAR(128),
  sex		CHAR DEFAULT '-' NOT NULL REFERENCES r_sex_setup(id),
  language	CHAR(2) NOT NULL REFERENCES r_lang_setup(id),
  passwd_plain	VARCHAR(10) NOT NULL,
  passwd_ht	VARCHAR(13) NOT NULL
) TYPE InnoDB;

-- 2009-02-17
-- alter table r_user add last_host VARCHAR(64);

-- 2009-08-06
create view r_user_ip as
select
  last_host,
  count(last_host) as count_host
from r_user
group by last_host
order by id;

-- 2010-02-09
create table r_host_ip_setup
(
  id CHAR(1) NOT NULL,
  name VARCHAR(8) NOT NULL,
  PRIMARY KEY(id)
);
INSERT INTO r_host_ip_setup(id, name)
VALUES (1, 'local'), (2, 'tor');

create table r_host_ip
(
  -- 15 = 4*3+3 = IPv4 only
  ip		VARCHAR(15) NOT NULL,
  type		INT UNSIGNED NOT NULL REFERENCES r_host_ip_setup(id),
  updated	INT UNSIGNED NOT NULL,
  PRIMARY KEY(ip, type)
);

-- drop view r_host_ip_recent;
create view r_host_ip_recent as
select
  r_host_ip.ip,
  r_host_ip_setup.name
from r_host_ip
left join r_host_ip_setup on r_host_ip.type = r_host_ip_setup.id
where r_host_ip.updated > UNIX_TIMESTAMP() - 60*60*24*7
order by r_host_ip.ip;

-- select * from r_host_ip where updated < UNIX_TIMESTAMP() - 60*60*24*7;
