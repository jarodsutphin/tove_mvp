-- Add hours_display to brand_config for the test restaurant.
-- brand_config is JSONB so no schema change is required — this is a data patch only.
update businesses
set brand_config = brand_config || '{"hours_display": "Tues–Sat 5pm–10pm + Sun 5pm–9pm"}'::jsonb
where slug = 'test-restaurant';
