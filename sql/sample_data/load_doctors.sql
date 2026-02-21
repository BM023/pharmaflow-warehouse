-- ============================================================================
-- Load Doctor Sample Data
-- 30 doctors (15 GPs + 15 Specialists)
-- ============================================================================

SET search_path TO dwh, public;

-- Insert 30 doctors with various specialties
INSERT INTO dwh.dim_doctor (
    doctor_id, hpcsa_registration_number,
    title, first_name, last_name,
    specialty, sub_specialty, practice_name, practice_type,
    years_in_practice,
    phone_number, email, practice_address, city, province,
    hospital_affiliations, is_referring_doctor,
    is_active, registration_date
) VALUES
-- General Practitioners (15)
('DOC-001', 'MP0123456', 'Dr', 'Sarah', 'Nkosi', 'General_Practitioner', NULL, 'Sandton Family Practice', 'Private', 15, '+27 11 234 5001', 'snkosi@sfp.co.za', '12 Rivonia Road, Sandton', 'Johannesburg', 'Gauteng', 'Sandton Mediclinic', FALSE, TRUE, '2010-03-15'),
('DOC-002', 'MP0234567', 'Dr', 'John', 'van der Merwe', 'General_Practitioner', NULL, 'Rosebank Medical Centre', 'Group_Practice', 22, '+27 11 234 5002', 'jvdm@rmc.co.za', 'The Mall, Rosebank', 'Johannesburg', 'Gauteng', 'Rosebank Hospital', FALSE, TRUE, '2003-06-20'),
('DOC-003', 'MP0345678', 'Dr', 'Fatima', 'Khan', 'General_Practitioner', NULL, 'Midrand Family Clinic', 'Private', 8, '+27 11 234 5003', 'fkhan@mfc.co.za', '200 Old Pretoria Road, Midrand', 'Johannesburg', 'Gauteng', NULL, FALSE, TRUE, '2017-01-10'),
('DOC-004', 'MP0456789', 'Dr', 'Thabo', 'Mokwena', 'General_Practitioner', NULL, 'Soweto Community Health', 'Public_Hospital', 12, '+27 11 234 5004', 'tmokwena@sch.gov.za', 'Chris Hani Baragwanath Hospital', 'Johannesburg', 'Gauteng', 'Chris Hani Baragwanath', FALSE, TRUE, '2013-09-05'),
('DOC-005', 'MP0567890', 'Dr', 'Lisa', 'Chen', 'General_Practitioner', NULL, 'CBD Quick Care', 'Clinic', 6, '+27 11 234 5005', 'lchen@cqc.co.za', '78 Commissioner Street, CBD', 'Johannesburg', 'Gauteng', NULL, FALSE, TRUE, '2019-04-12'),
('DOC-006', 'MP0678901', 'Dr', 'Ahmed', 'Patel', 'General_Practitioner', NULL, 'Lenasia Medical Practice', 'Private', 18, '+27 11 234 5006', 'apatel@lmp.co.za', '45 Nirvana Drive, Lenasia', 'Johannesburg', 'Gauteng', NULL, FALSE, TRUE, '2007-11-22'),
('DOC-007', 'MP0789012', 'Dr', 'Nomsa', 'Khumalo', 'General_Practitioner', NULL, 'Alexandra Clinic', 'Clinic', 10, '+27 11 234 5007', 'nkhumalo@ac.co.za', '12 Selborne Road, Alexandra', 'Johannesburg', 'Gauteng', NULL, FALSE, TRUE, '2015-02-18'),
('DOC-008', 'MP0890123', 'Dr', 'David', 'Botha', 'General_Practitioner', NULL, 'Fourways Family Health', 'Group_Practice', 14, '+27 11 234 5008', 'dbotha@ffh.co.za', 'Cedar Square, Fourways', 'Johannesburg', 'Gauteng', 'Fourways Life Hospital', FALSE, TRUE, '2011-07-30'),
('DOC-009', 'MP0901234', 'Dr', 'Precious', 'Dlamini', 'General_Practitioner', NULL, 'Bryanston Medical', 'Private', 9, '+27 11 234 5009', 'pdlamini@bm.co.za', '267 Main Road, Bryanston', 'Johannesburg', 'Gauteng', NULL, FALSE, TRUE, '2016-05-14'),
('DOC-010', 'MP1012345', 'Dr', 'Michael', 'O''Brien', 'General_Practitioner', NULL, 'Greenside Practice', 'Private', 25, '+27 11 234 5010', 'mobrien@gp.co.za', '34 Gleneagles Road, Greenside', 'Johannesburg', 'Gauteng', 'Parklane Hospital', FALSE, TRUE, '2000-01-08'),
('DOC-011', 'MP1123456', 'Dr', 'Zanele', 'Sithole', 'General_Practitioner', NULL, 'Orange Grove Clinic', 'Clinic', 7, '+27 11 234 5011', 'zsithole@ogc.co.za', '56 Louis Botha Ave, Orange Grove', 'Johannesburg', 'Gauteng', NULL, FALSE, TRUE, '2018-08-25'),
('DOC-012', 'MP1234567', 'Dr', 'Pieter', 'Kruger', 'General_Practitioner', NULL, 'Randburg Family Doctors', 'Group_Practice', 20, '+27 11 234 5012', 'pkruger@rfd.co.za', 'Northlands Corner, Randburg', 'Johannesburg', 'Gauteng', 'Olivedale Hospital', FALSE, TRUE, '2005-03-19'),
('DOC-013', 'MP1345678', 'Dr', 'Lerato', 'Mahlangu', 'General_Practitioner', NULL, 'Melville Medical Centre', 'Private', 11, '+27 11 234 5013', 'lmahlangu@mmc.co.za', '12 Main Road, Melville', 'Johannesburg', 'Gauteng', NULL, FALSE, TRUE, '2014-10-07'),
('DOC-014', 'MP1456789', 'Dr', 'James', 'Smith', 'General_Practitioner', NULL, 'Benoni Health Practice', 'Private', 16, '+27 11 234 5014', 'jsmith@bhp.co.za', '78 Princes Ave, Benoni', 'Johannesburg', 'Gauteng', NULL, FALSE, TRUE, '2009-06-13'),
('DOC-015', 'MP1567890', 'Dr', 'Nandi', 'Zulu', 'General_Practitioner', NULL, 'Diepsloot Community Clinic', 'Public_Hospital', 5, '+27 11 234 5015', 'nzulu@dcc.gov.za', 'William Nicol Drive, Diepsloot', 'Johannesburg', 'Gauteng', NULL, FALSE, TRUE, '2020-09-01'),

-- Specialists (15)
('DOC-016', 'MP1678901', 'Dr', 'Rajesh', 'Naicker', 'Cardiologist', 'Interventional Cardiology', 'Morningside Heart Institute', 'Private', 19, '+27 11 234 5016', 'rnaicker@mhi.co.za', '45 Rivonia Road, Morningside', 'Johannesburg', 'Gauteng', 'Morningside Mediclinic', TRUE, TRUE, '2006-02-14'),
('DOC-017', 'MP1789012', 'Prof', 'Elizabeth', 'Coetzee', 'Endocrinologist', 'Diabetes Management', 'Wits Diabetes Centre', 'Private', 28, '+27 11 234 5017', 'ecoetzee@wdc.co.za', 'Wits Medical School, Parktown', 'Johannesburg', 'Gauteng', 'Charlotte Maxeke Hospital', TRUE, TRUE, '1997-07-22'),
('DOC-018', 'MP1890123', 'Dr', 'Sipho', 'Ndaba', 'Pediatrician', 'General Pediatrics', 'Kids First Pediatrics', 'Private', 13, '+27 11 234 5018', 'sndaba@kfp.co.za', 'Sandton Mediclinic, Sandton', 'Johannesburg', 'Gauteng', 'Sandton Mediclinic', TRUE, TRUE, '2012-04-08'),
('DOC-019', 'MP1901234', 'Dr', 'Michelle', 'du Toit', 'Gynecologist', 'Obstetrics', 'Netcare Rosebank', 'Private', 17, '+27 11 234 5019', 'mdutoit@nr.co.za', 'Netcare Rosebank Hospital', 'Johannesburg', 'Gauteng', 'Netcare Rosebank', TRUE, TRUE, '2008-11-30'),
('DOC-020', 'MP2012345', 'Dr', 'Yusuf', 'Essop', 'Psychiatrist', 'Adult Psychiatry', 'Mind Matters Clinic', 'Private', 15, '+27 11 234 5020', 'yessop@mmc.co.za', '12 Fredman Drive, Sandton', 'Johannesburg', 'Gauteng', NULL, TRUE, TRUE, '2010-05-16'),
('DOC-021', 'MP2123456', 'Dr', 'Thabiso', 'Molefe', 'Orthopedic_Surgeon', 'Sports Medicine', 'Sports Ortho Specialists', 'Private', 21, '+27 11 234 5021', 'tmolefe@sos.co.za', 'Life Fourways Hospital', 'Johannesburg', 'Gauteng', 'Life Fourways', TRUE, TRUE, '2004-08-12'),
('DOC-022', 'MP2234567', 'Dr', 'Karen', 'Jacobs', 'Dermatologist', 'Medical Dermatology', 'Skin Health Clinic', 'Private', 12, '+27 11 234 5022', 'kjacobs@shc.co.za', '34 Jan Smuts Ave, Rosebank', 'Johannesburg', 'Gauteng', NULL, TRUE, TRUE, '2013-01-25'),
('DOC-023', 'MP2345678', 'Dr', 'Bongani', 'Mthembu', 'Neurologist', 'Epilepsy', 'Neuro Care Centre', 'Private', 16, '+27 11 234 5023', 'bmthembu@ncc.co.za', 'Morningside Mediclinic', 'Johannesburg', 'Gauteng', 'Morningside Mediclinic', TRUE, TRUE, '2009-09-19'),
('DOC-024', 'MP2456789', 'Dr', 'Anita', 'Singh', 'Oncologist', 'Medical Oncology', 'Cancer Care Centre', 'Private', 14, '+27 11 234 5024', 'asingh@ccc.co.za', 'Sandton Oncology Centre', 'Johannesburg', 'Gauteng', 'Sandton Mediclinic', TRUE, TRUE, '2011-03-07'),
('DOC-025', 'MP2567890', 'Dr', 'Willem', 'Vorster', 'Pulmonologist', 'Critical Care', 'Lung Health Institute', 'Private', 18, '+27 11 234 5025', 'wvorster@lhi.co.za', 'Milpark Hospital', 'Johannesburg', 'Gauteng', 'Netcare Milpark', TRUE, TRUE, '2007-06-23'),
('DOC-026', 'MP2678901', 'Dr', 'Naledi', 'Mokoena', 'Rheumatologist', 'Autoimmune Diseases', 'Arthritis Centre JHB', 'Private', 10, '+27 11 234 5026', 'nmokoena@acjhb.co.za', '56 Rivonia Road, Sandton', 'Johannesburg', 'Gauteng', NULL, TRUE, TRUE, '2015-11-14'),
('DOC-027', 'MP2789012', 'Dr', 'Christopher', 'Brown', 'Urologist', 'General Urology', 'Urology Associates', 'Private', 22, '+27 11 234 5027', 'cbrown@ua.co.za', 'Rosebank Hospital', 'Johannesburg', 'Gauteng', 'Netcare Rosebank', TRUE, TRUE, '2003-04-29'),
('DOC-028', 'MP2890123', 'Dr', 'Gugu', 'Dube', 'Hematologist', 'Blood Disorders', 'Blood Health Clinic', 'Private', 11, '+27 11 234 5028', 'gdube@bhc.co.za', 'Charlotte Maxeke Hospital', 'Johannesburg', 'Gauteng', 'Charlotte Maxeke', TRUE, TRUE, '2014-07-18'),
('DOC-029', 'MP2901234', 'Dr', 'Heinrich', 'Muller', 'Gastroenterologist', 'Hepatology', 'Digestive Health Centre', 'Private', 20, '+27 11 234 5029', 'hmuller@dhc.co.za', 'Morningside Mediclinic', 'Johannesburg', 'Gauteng', 'Morningside Mediclinic', TRUE, TRUE, '2005-10-11'),
('DOC-030', 'MP3012345', 'Dr', 'Thembi', 'Radebe', 'Infectious_Disease', 'HIV/AIDS Specialist', 'ID Specialists JHB', 'Public_Hospital', 13, '+27 11 234 5030', 'tradebe@ids.gov.za', 'Helen Joseph Hospital', 'Johannesburg', 'Gauteng', 'Helen Joseph Hospital', TRUE, TRUE, '2012-12-03');

-- Verify
SELECT COUNT(*) as doctor_count FROM dwh.dim_doctor;
SELECT COUNT(*) as gp_count FROM dwh.dim_doctor WHERE specialty = 'General_Practitioner';
SELECT COUNT(*) as specialist_count FROM dwh.dim_doctor WHERE specialty != 'General_Practitioner';