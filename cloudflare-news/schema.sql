-- News sources registry
CREATE TABLE IF NOT EXISTS sources (
  id          TEXT PRIMARY KEY,   -- e.g. "motorsport-f1"
  name        TEXT NOT NULL,
  feed_url    TEXT NOT NULL,
  category    TEXT NOT NULL,      -- "racing" | "road_cars" | "modified"
  subcategory TEXT,               -- "f1" | "nascar" | "indycar" | "gt3" | "drifting" | "jdm" | etc.
  active      INTEGER NOT NULL DEFAULT 1
);

-- Ingested articles (pre-clustering)
CREATE TABLE IF NOT EXISTS articles (
  id           TEXT PRIMARY KEY,  -- sha256 of canonical_url
  source_id    TEXT NOT NULL REFERENCES sources(id),
  title        TEXT NOT NULL,
  summary      TEXT,
  thumbnail    TEXT,
  url          TEXT NOT NULL,
  published_at INTEGER NOT NULL,  -- unix seconds
  fetched_at   INTEGER NOT NULL,
  category     TEXT NOT NULL,
  subcategory  TEXT,
  cluster_id   TEXT,              -- FK into clusters, set after clustering
  UNIQUE(url)
);

-- Story clusters (one cluster per underlying story/event)
CREATE TABLE IF NOT EXISTS clusters (
  id            TEXT PRIMARY KEY,  -- sha256 of canonical story fingerprint
  title         TEXT NOT NULL,     -- headline from the highest-ranked source
  summary       TEXT,
  thumbnail     TEXT,
  category      TEXT NOT NULL,
  subcategory   TEXT,
  source_count  INTEGER NOT NULL DEFAULT 1,
  first_seen_at INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_articles_cluster    ON articles(cluster_id);
CREATE INDEX IF NOT EXISTS idx_articles_category   ON articles(category, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_clusters_category   ON clusters(category, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_clusters_subcategory ON clusters(subcategory, last_seen_at DESC);

-- Seed sources
-- Feed URLs verified live 2026-07-29. Dead sources removed; replacements noted.
INSERT OR IGNORE INTO sources VALUES
  -- Racing: F1
  ('motorsport-f1',    'Motorsport.com F1',     'https://www.motorsport.com/rss/f1/news/',          'racing', 'f1',       1),
  ('racefans',         'RaceFans',               'https://www.racefans.net/feed/',                   'racing', 'f1',       1),
  ('therace',          'The Race',               'https://www.the-race.com/rss/',                    'racing', 'f1',       1),
  -- Racing: NASCAR
  ('motorsport-nascar','Motorsport.com NASCAR',  'https://www.motorsport.com/rss/nascar-cup/news/',  'racing', 'nascar',   1),
  -- Racing: IndyCar
  ('motorsport-indy',  'Motorsport.com IndyCar', 'https://www.motorsport.com/rss/indycar/news/',     'racing', 'indycar',  1),
  -- Racing: GT3/WEC/IMSA (replaces dead gtreport.com)
  ('sportscar365',     'Sportscar365',           'https://sportscar365.com/feed/',                   'racing', 'gt3',      1),
  -- Racing: Drifting (formulad confirmed live; drifting.com inactive — excluded)
  ('formulad',         'Formula DRIFT',          'https://news.formulad.com/feed/',                  'racing', 'drifting', 1),
  -- Road Cars: major pubs
  ('motor1',           'Motor1',                 'https://www.motor1.com/rss/news/all/',             'road_cars', NULL,    1),
  ('caranddriver',     'Car and Driver',         'https://www.caranddriver.com/rss/all.xml/',        'road_cars', NULL,    1),
  ('thedrive',         'The Drive',              'https://www.thedrive.com/feed',                    'road_cars', NULL,    1),
  ('carscoops',        'Carscoops',              'https://www.carscoops.com/feed/',                  'road_cars', NULL,    1),
  ('jalopnik',         'Jalopnik',               'https://www.jalopnik.com/feed/',                   'road_cars', NULL,    1),
  -- Modified/Tuning & enthusiast
  -- stanceauto.co.uk and grassrootsmotorsports.com have no working RSS feed as of 2026-07-29.
  -- HotCars covers muscle cars, modded builds, and classic car culture — active daily feed.
  ('hotcars',          'HotCars',                'https://www.hotcars.com/feed/',                    'modified', NULL,     1),
  ('stanceworks',      'StanceWorks',            'https://stanceworks.com/feed/',                    'modified', NULL,     1),
  -- Road Cars: additional pubs (verified live 2026-07-29)
  ('autoblog',         'Autoblog',               'https://www.autoblog.com/rss.xml',                 'road_cars', NULL,    1),
  ('autocar',          'Autocar',                'https://www.autocar.co.uk/rss',                    'road_cars', NULL,    1),
  ('roadandtrack',     'Road & Track',           'https://www.roadandtrack.com/rss/all.xml/',        'road_cars', NULL,    1),
  ('autoexpress',      'Auto Express',           'https://www.autoexpress.co.uk/feed/all',           'road_cars', NULL,    1),
  ('carthrottle',      'Car Throttle',           'https://www.carthrottle.com/rss',                  'road_cars', NULL,    1),
  -- Racing: WRC / Rally
  ('dirtfish',         'DirtFish',               'https://dirtfish.com/feed/',                       'racing', 'rally',   1),
  -- Racing: Autosport (broad motorsport coverage)
  ('autosport',        'Autosport',              'https://www.autosport.com/rss/all/news/',           'racing', NULL,      1);
