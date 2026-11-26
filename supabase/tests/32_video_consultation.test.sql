-- The video consultation is a service like any other: patients can book it, and its length is fixed.
begin;
select plan(3);
select is((select name from public.services where code = 'D9995'), 'Video consultation', 'the D9995 service exists');
select ok((select self_bookable and active from public.services where code = 'D9995'), 'patients can book it themselves');
select is((select duration_minutes from public.services where code = 'D9995'), 20, 'it is a 20-minute visit');
select * from finish();
rollback;
