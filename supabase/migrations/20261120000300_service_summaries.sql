-- A one-line, plain-language description of each service, shown to patients before they book.
alter table public.services add column summary text check (char_length(summary) <= 200);

-- Existing rows (staging); fresh databases get the same text from seed.sql.
update public.services set summary = 'A full check of your teeth, gums and bite, with X-rays if needed, and a plan for anything we find.' where code = 'D0150';
update public.services set summary = 'A hygienist removes plaque and tartar, polishes your teeth and shows you what to focus on at home.' where code = 'D1110';
update public.services set summary = 'A gentle clean and polish for children, with tips for brushing and a check on growing teeth.' where code = 'D1120';
update public.services set summary = 'A tooth-coloured filling that repairs a small cavity on one side of a tooth, usually in one visit.' where code = 'D2391';
update public.services set summary = 'Removing a tooth that can be lifted out simply, with numbing so you feel pressure, not pain.' where code = 'D7140';
update public.services set summary = 'Treats infection inside a back tooth and seals it, so you can keep the tooth instead of losing it.' where code = 'D3330';
update public.services set summary = 'Placing a titanium post to replace a missing tooth root, planned with a 3D scan first.' where code = 'D6010';
update public.services set summary = 'Straightening your teeth with clear, removable aligners, worn about 22 hours a day.' where code = 'D8090';
update public.services set summary = 'Brightening the colour of your teeth safely in the clinic, after a quick check that it suits you.' where code = 'D9972';
update public.services set summary = 'A full removable set of upper teeth, made to fit your mouth over a few fittings.' where code = 'D5110';
update public.services set summary = 'Quick relief for dental pain or injury. Call us and we will see you as soon as we can.' where code = 'D9110';
