-- Demo data for the fictional clinic used in this project.

INSERT INTO dental_clinic.clinic (name, time_zone, slot_minutes)
VALUES ('Maple Grove Dental Studio', 'America/New_York', 30);

INSERT INTO dental_clinic.business_hours (weekday, opens_at, closes_at) VALUES
  (1, '08:00', '18:00'),
  (2, '08:00', '18:00'),
  (3, '08:00', '18:00'),
  (4, '08:00', '18:00'),
  (5, '08:00', '18:00'),
  (6, '09:00', '13:00');

INSERT INTO dental_clinic.services (name, duration_minutes, price_from) VALUES
  ('Toothache / emergency exam',            30,  79),
  ('New patient exam + X-rays + cleaning',  60, 149),
  ('Routine cleaning',                      60,  99),
  ('Teeth whitening (in-office)',           90, 350),
  ('Tooth-colored filling',                 60, 180),
  ('Root canal',                            90, 900),
  ('Dental implant consultation',           30,   0),
  ('Invisalign consultation',               30,   0);
