-- ============================================================================
-- Load Medication Sample Data
-- 60 common South African medications across all categories
-- ============================================================================

SET search_path TO dwh, public;

-- Insert 60 common medications used in SA pharmacies
INSERT INTO dwh.dim_medication (
    medication_id, barcode, medication_name, generic_name, scientific_name,
    manufacturer, distributor, dosage_form, strength, pack_size, unit_of_measure,
    category_key, therapeutic_class, schedule_classification,
    requires_prescription, is_controlled_substance, is_generic,
    unit_cost_price, unit_retail_price,
    typical_shelf_life_days, minimum_order_quantity, reorder_lead_time_days,
    storage_requirements, is_fragile, is_high_value,
    is_seasonal, seasonal_peak_months, is_active
) VALUES
-- CHRONIC MEDICATIONS - Fast Movers (Category 1)
('MED-001', '6001234567890', 'Glucophage 500mg', 'Metformin', 'Metformin Hydrochloride', 'Merck', 'Aspen Pharmacare', 'Tablet', '500mg', 60, 'Tablets', 1, 'Antidiabetic', 'S3', TRUE, FALSE, FALSE, 45.00, 89.90, 730, 10, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-002', '6001234567891', 'Amaryl 2mg', 'Glimepiride', 'Glimepiride', 'Sanofi', 'Aspen Pharmacare', 'Tablet', '2mg', 30, 'Tablets', 1, 'Antidiabetic', 'S3', TRUE, FALSE, FALSE, 78.00, 156.50, 730, 5, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-003', '6001234567892', 'Atenolol 50mg', 'Atenolol', 'Atenolol', 'Adcock Ingram', 'Adcock Ingram', 'Tablet', '50mg', 28, 'Tablets', 1, 'Cardiovascular', 'S3', TRUE, FALSE, TRUE, 12.50, 24.90, 730, 20, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-004', '6001234567893', 'Pharmapress 10mg', 'Enalapril', 'Enalapril Maleate', 'Aspen', 'Aspen Pharmacare', 'Tablet', '10mg', 28, 'Tablets', 1, 'Cardiovascular', 'S3', TRUE, FALSE, TRUE, 18.00, 35.90, 730, 15, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-005', '6001234567894', 'Atrovent 20mcg', 'Ipratropium', 'Ipratropium Bromide', 'Boehringer', 'Imperial Health', 'Inhaler', '20mcg', 200, 'Doses', 1, 'Respiratory', 'S2', TRUE, FALSE, FALSE, 89.00, 178.50, 730, 5, 3, 'Room Temperature', TRUE, FALSE, FALSE, NULL, TRUE),

-- CHRONIC MEDICATIONS - Medium Movers (Category 2)
('MED-006', '6001234567895', 'Eltroxin 100mcg', 'Levothyroxine', 'Levothyroxine Sodium', 'Aspen', 'Aspen Pharmacare', 'Tablet', '100mcg', 30, 'Tablets', 2, 'Thyroid', 'S3', TRUE, FALSE, FALSE, 34.00, 67.90, 730, 10, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-007', '6001234567896', 'Warfarin 5mg', 'Warfarin', 'Warfarin Sodium', 'Aspen', 'Aspen Pharmacare', 'Tablet', '5mg', 100, 'Tablets', 2, 'Anticoagulant', 'S4', TRUE, FALSE, TRUE, 56.00, 112.50, 730, 5, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-008', '6001234567897', 'Urbanol 10mg', 'Clobazam', 'Clobazam', 'Sanofi', 'Aspen Pharmacare', 'Tablet', '10mg', 30, 'Tablets', 2, 'Anticonvulsant', 'S5', TRUE, TRUE, FALSE, 145.00, 289.90, 730, 3, 3, 'Room Temperature', FALSE, TRUE, FALSE, NULL, TRUE),

-- SEASONAL MEDICATIONS - Fast Movers (Category 4)
('MED-009', '6001234567898', 'Corenza C', 'Paracetamol + Phenylephrine + Vitamin C', 'Multi-ingredient', 'Adcock Ingram', 'Adcock Ingram', 'Tablet', 'Combination', 24, 'Tablets', 4, 'Cold & Flu', 'S1', FALSE, FALSE, FALSE, 34.00, 67.90, 730, 20, 1, 'Room Temperature', FALSE, FALSE, TRUE, '5,6,7,8', TRUE),
('MED-010', '6001234567899', 'Flutex Syrup', 'Paracetamol + Promethazine', 'Multi-ingredient', 'Aspen', 'Aspen Pharmacare', 'Liquid', '100ml', 1, 'ml', 4, 'Cold & Flu', 'S2', FALSE, FALSE, FALSE, 23.00, 45.90, 730, 15, 2, 'Room Temperature', TRUE, FALSE, TRUE, '5,6,7,8,9', TRUE),
('MED-011', '6001234567900', 'Allergex 5mg', 'Chlorphenamine', 'Chlorphenamine Maleate', 'Aspen', 'Aspen Pharmacare', 'Tablet', '5mg', 30, 'Tablets', 4, 'Antihistamine', 'S2', FALSE, FALSE, TRUE, 18.00, 35.90, 730, 25, 1, 'Room Temperature', FALSE, FALSE, TRUE, '8,9,10,11', TRUE),
('MED-012', '6001234567901', 'Iliadin Nasal Spray', 'Oxymetazoline', 'Oxymetazoline HCl', 'Bayer', 'Imperial Health', 'Spray', '0.05%', 10, 'ml', 4, 'Decongestant', 'S1', FALSE, FALSE, FALSE, 34.00, 67.50, 730, 20, 2, 'Room Temperature', FALSE, FALSE, TRUE, '5,6,7,8', TRUE),

-- REGULAR MEDICATIONS - Fast Movers (Category 7)
('MED-013', '6001234567902', 'Panado 500mg', 'Paracetamol', 'Paracetamol', 'Aspen', 'Aspen Pharmacare', 'Tablet', '500mg', 24, 'Tablets', 7, 'Analgesic', 'S0', FALSE, FALSE, TRUE, 8.50, 16.90, 730, 50, 1, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-014', '6001234567903', 'Grandpa Headache Powder', 'Paracetamol + Aspirin + Caffeine', 'Multi-ingredient', 'Adcock Ingram', 'Adcock Ingram', 'Powder', 'Combination', 24, 'Sachets', 7, 'Analgesic', 'S1', FALSE, FALSE, FALSE, 15.00, 29.90, 730, 40, 1, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-015', '6001234567904', 'Disprin 300mg', 'Aspirin', 'Acetylsalicylic Acid', 'Reckitt Benckiser', 'UniPharm', 'Tablet', '300mg', 24, 'Tablets', 7, 'Analgesic', 'S1', FALSE, FALSE, TRUE, 9.00, 17.90, 730, 45, 1, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-016', '6001234567905', 'Ibuprofen 200mg', 'Ibuprofen', 'Ibuprofen', 'Adcock Ingram', 'Adcock Ingram', 'Tablet', '200mg', 24, 'Tablets', 7, 'NSAID', 'S1', FALSE, FALSE, TRUE, 11.00, 21.90, 730, 40, 1, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-017', '6001234567906', 'Gaviscon Liquid', 'Sodium Alginate + Calcium Carbonate', 'Multi-ingredient', 'Reckitt Benckiser', 'Imperial Health', 'Liquid', '300ml', 1, 'ml', 7, 'Antacid', 'S0', FALSE, FALSE, FALSE, 45.00, 89.90, 730, 20, 2, 'Room Temperature', TRUE, FALSE, FALSE, NULL, TRUE),
('MED-018', '6001234567907', 'Rennie Tablets', 'Calcium Carbonate + Magnesium Carbonate', 'Multi-ingredient', 'Bayer', 'UniPharm', 'Tablet', 'Combination', 24, 'Tablets', 7, 'Antacid', 'S0', FALSE, FALSE, FALSE, 18.00, 35.90, 730, 30, 1, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-019', '6001234567908', 'Bioplus 500mg', 'Vitamin C', 'Ascorbic Acid', 'Adcock Ingram', 'Adcock Ingram', 'Tablet', '500mg', 30, 'Tablets', 7, 'Vitamin', 'S0', FALSE, FALSE, FALSE, 23.00, 45.90, 730, 25, 1, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-020', '6001234567909', 'Feminax Tablets', 'Paracetamol + Pamabrom + Hyoscine', 'Multi-ingredient', 'Bayer', 'Imperial Health', 'Tablet', 'Combination', 20, 'Tablets', 7, 'Analgesic', 'S2', FALSE, FALSE, FALSE, 34.00, 67.90, 730, 20, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),

-- ACUTE MEDICATIONS - Fast Movers (Category 10)
('MED-021', '6001234567910', 'Amoxil 500mg', 'Amoxicillin', 'Amoxicillin Trihydrate', 'GSK', 'Aspen Pharmacare', 'Capsule', '500mg', 21, 'Capsules', 10, 'Antibiotic', 'S3', TRUE, FALSE, FALSE, 89.00, 178.50, 730, 15, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-022', '6001234567911', 'Augmentin 625mg', 'Amoxicillin + Clavulanic Acid', 'Multi-ingredient', 'GSK', 'Aspen Pharmacare', 'Tablet', '625mg', 14, 'Tablets', 10, 'Antibiotic', 'S3', TRUE, FALSE, FALSE, 145.00, 289.90, 730, 10, 2, 'Room Temperature', FALSE, TRUE, FALSE, NULL, TRUE),
('MED-023', '6001234567912', 'Ciprobay 500mg', 'Ciprofloxacin', 'Ciprofloxacin HCl', 'Bayer', 'Imperial Health', 'Tablet', '500mg', 10, 'Tablets', 10, 'Antibiotic', 'S4', TRUE, FALSE, FALSE, 167.00, 334.50, 730, 8, 3, 'Room Temperature', FALSE, TRUE, FALSE, NULL, TRUE),
('MED-024', '6001234567913', 'Adco-Dol Syrup', 'Paracetamol', 'Paracetamol', 'Adcock Ingram', 'Adcock Ingram', 'Liquid', '100ml', 1, 'ml', 10, 'Analgesic', 'S0', FALSE, FALSE, TRUE, 18.00, 35.90, 730, 30, 1, 'Room Temperature', TRUE, FALSE, FALSE, NULL, TRUE),

-- Additional medications (MED-025 to MED-060)
('MED-025', '6001234567914', 'Stemetil 5mg', 'Prochlorperazine', 'Prochlorperazine Maleate', 'Sanofi', 'Aspen Pharmacare', 'Tablet', '5mg', 25, 'Tablets', 8, 'Antiemetic', 'S3', TRUE, FALSE, FALSE, 45.00, 89.90, 730, 15, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-026', '6001234567915', 'Loperamide 2mg', 'Loperamide', 'Loperamide HCl', 'Aspen', 'Aspen Pharmacare', 'Capsule', '2mg', 20, 'Capsules', 8, 'Antidiarrheal', 'S2', FALSE, FALSE, TRUE, 23.00, 45.90, 730, 20, 1, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-027', '6001234567916', 'Buscopan 10mg', 'Hyoscine', 'Hyoscine Butylbromide', 'Boehringer', 'Imperial Health', 'Tablet', '10mg', 20, 'Tablets', 8, 'Antispasmodic', 'S2', FALSE, FALSE, FALSE, 34.00, 67.90, 730, 20, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-028', '6001234567917', 'Adco-Napamol Syrup', 'Paracetamol', 'Paracetamol', 'Adcock Ingram', 'Adcock Ingram', 'Liquid', '100ml', 1, 'ml', 7, 'Analgesic', 'S0', FALSE, FALSE, TRUE, 16.00, 31.90, 730, 35, 1, 'Room Temperature', TRUE, FALSE, FALSE, NULL, TRUE),
('MED-029', '6001234567918', 'Stopayne Tablets', 'Paracetamol + Codeine', 'Multi-ingredient', 'Aspen', 'Aspen Pharmacare', 'Tablet', 'Combination', 20, 'Tablets', 8, 'Analgesic', 'S3', TRUE, FALSE, FALSE, 34.00, 67.90, 730, 15, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-030', '6001234567919', 'Betapyn Tablets', 'Paracetamol + Propyphenazone + Caffeine', 'Multi-ingredient', 'Adcock Ingram', 'Adcock Ingram', 'Tablet', 'Combination', 24, 'Tablets', 7, 'Analgesic', 'S1', FALSE, FALSE, FALSE, 19.00, 37.90, 730, 25, 1, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-031', '6001234567920', 'Solal Vitamin D3', 'Cholecalciferol', 'Vitamin D3', 'Solal', 'UniPharm', 'Capsule', '1000IU', 60, 'Capsules', 7, 'Vitamin', 'S0', FALSE, FALSE, FALSE, 67.00, 134.50, 730, 15, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-032', '6001234567921', 'Pharmaton Capsules', 'Multivitamin + Ginseng', 'Multi-ingredient', 'Boehringer', 'Imperial Health', 'Capsule', 'Combination', 30, 'Capsules', 8, 'Vitamin', 'S0', FALSE, FALSE, FALSE, 89.00, 178.50, 730, 10, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-033', '6001234567922', 'Berocca Boost', 'B-Complex + Vitamin C + Guarana', 'Multi-ingredient', 'Bayer', 'UniPharm', 'Tablet', 'Combination', 15, 'Tablets', 7, 'Vitamin', 'S0', FALSE, FALSE, FALSE, 78.00, 156.50, 730, 12, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-034', '6001234567923', 'Allergex Syrup', 'Chlorphenamine', 'Chlorphenamine Maleate', 'Aspen', 'Aspen Pharmacare', 'Liquid', '100ml', 1, 'ml', 5, 'Antihistamine', 'S2', FALSE, FALSE, TRUE, 23.00, 45.90, 730, 20, 1, 'Room Temperature', TRUE, FALSE, TRUE, '8,9,10,11', TRUE),
('MED-035', '6001234567924', 'Telfast 120mg', 'Fexofenadine', 'Fexofenadine HCl', 'Sanofi', 'Aspen Pharmacare', 'Tablet', '120mg', 10, 'Tablets', 5, 'Antihistamine', 'S2', FALSE, FALSE, FALSE, 67.00, 134.50, 730, 15, 2, 'Room Temperature', FALSE, FALSE, TRUE, '8,9,10,11', TRUE),
('MED-036', '6001234567925', 'Nexium 20mg', 'Esomeprazole', 'Esomeprazole Magnesium', 'AstraZeneca', 'Aspen Pharmacare', 'Capsule', '20mg', 28, 'Capsules', 2, 'Proton Pump Inhibitor', 'S3', TRUE, FALSE, FALSE, 145.00, 289.90, 730, 8, 3, 'Room Temperature', FALSE, TRUE, FALSE, NULL, TRUE),
('MED-037', '6001234567926', 'Losec 20mg', 'Omeprazole', 'Omeprazole Magnesium', 'AstraZeneca', 'Aspen Pharmacare', 'Capsule', '20mg', 28, 'Capsules', 2, 'Proton Pump Inhibitor', 'S3', TRUE, FALSE, FALSE, 134.00, 268.50, 730, 10, 3, 'Room Temperature', FALSE, TRUE, FALSE, NULL, TRUE),
('MED-038', '6001234567927', 'Adco-Simvastatin 20mg', 'Simvastatin', 'Simvastatin', 'Adcock Ingram', 'Adcock Ingram', 'Tablet', '20mg', 30, 'Tablets', 1, 'Statin', 'S4', TRUE, FALSE, TRUE, 56.00, 112.50, 730, 12, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-039', '6001234567928', 'Crestor 10mg', 'Rosuvastatin', 'Rosuvastatin Calcium', 'AstraZeneca', 'Aspen Pharmacare', 'Tablet', '10mg', 28, 'Tablets', 1, 'Statin', 'S4', TRUE, FALSE, FALSE, 178.00, 356.50, 730, 8, 3, 'Room Temperature', FALSE, TRUE, FALSE, NULL, TRUE),
('MED-040', '6001234567929', 'Plavix 75mg', 'Clopidogrel', 'Clopidogrel Bisulfate', 'Sanofi', 'Aspen Pharmacare', 'Tablet', '75mg', 28, 'Tablets', 1, 'Antiplatelet', 'S4', TRUE, FALSE, FALSE, 234.00, 468.50, 730, 5, 3, 'Room Temperature', FALSE, TRUE, FALSE, NULL, TRUE),
('MED-041', '6001234567930', 'Ecotrin 100mg', 'Aspirin', 'Acetylsalicylic Acid', 'GSK', 'UniPharm', 'Tablet', '100mg', 30, 'Tablets', 1, 'Antiplatelet', 'S2', FALSE, FALSE, TRUE, 23.00, 45.90, 730, 20, 1, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-042', '6001234567931', 'Pharmapress Co 5/12.5mg', 'Enalapril + HCTZ', 'Multi-ingredient', 'Aspen', 'Aspen Pharmacare', 'Tablet', 'Combination', 28, 'Tablets', 1, 'Cardiovascular', 'S3', TRUE, FALSE, TRUE, 34.00, 67.90, 730, 15, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-043', '6001234567932', 'Norvasc 5mg', 'Amlodipine', 'Amlodipine Besylate', 'Pfizer', 'Aspen Pharmacare', 'Tablet', '5mg', 30, 'Tablets', 1, 'Cardiovascular', 'S3', TRUE, FALSE, FALSE, 67.00, 134.50, 730, 12, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-044', '6001234567933', 'Adco-Zolpidem 10mg', 'Zolpidem', 'Zolpidem Tartrate', 'Adcock Ingram', 'Adcock Ingram', 'Tablet', '10mg', 30, 'Tablets', 2, 'Sedative', 'S6', TRUE, TRUE, TRUE, 45.00, 89.90, 730, 10, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-045', '6001234567934', 'Stilnox 10mg', 'Zolpidem', 'Zolpidem Tartrate', 'Sanofi', 'Aspen Pharmacare', 'Tablet', '10mg', 10, 'Tablets', 2, 'Sedative', 'S6', TRUE, TRUE, FALSE, 89.00, 178.50, 730, 8, 3, 'Room Temperature', FALSE, TRUE, FALSE, NULL, TRUE),
('MED-046', '6001234567935', 'Cipramil 20mg', 'Citalopram', 'Citalopram HBr', 'Lundbeck', 'Aspen Pharmacare', 'Tablet', '20mg', 28, 'Tablets', 2, 'Antidepressant', 'S5', TRUE, TRUE, FALSE, 145.00, 289.90, 730, 8, 3, 'Room Temperature', FALSE, TRUE, FALSE, NULL, TRUE),
('MED-047', '6001234567936', 'Trepiline 25mg', 'Amitriptyline', 'Amitriptyline HCl', 'Aspen', 'Aspen Pharmacare', 'Tablet', '25mg', 30, 'Tablets', 2, 'Antidepressant', 'S4', TRUE, FALSE, TRUE, 34.00, 67.90, 730, 15, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-048', '6001234567937', 'Venteze Inhaler', 'Salbutamol', 'Salbutamol Sulfate', 'Aspen', 'Aspen Pharmacare', 'Inhaler', '100mcg', 200, 'Doses', 1, 'Bronchodilator', 'S2', TRUE, FALSE, TRUE, 45.00, 89.90, 730, 15, 2, 'Room Temperature', TRUE, FALSE, FALSE, NULL, TRUE),
('MED-049', '6001234567938', 'Flixotide 125mcg', 'Fluticasone', 'Fluticasone Propionate', 'GSK', 'Aspen Pharmacare', 'Inhaler', '125mcg', 120, 'Doses', 1, 'Corticosteroid', 'S3', TRUE, FALSE, FALSE, 178.00, 356.50, 730, 8, 3, 'Room Temperature', TRUE, TRUE, FALSE, NULL, TRUE),
('MED-050', '6001234567939', 'Seretide 250 Diskus', 'Fluticasone + Salmeterol', 'Multi-ingredient', 'GSK', 'Aspen Pharmacare', 'Inhaler', 'Combination', 60, 'Doses', 1, 'Respiratory', 'S4', TRUE, FALSE, FALSE, 345.00, 690.50, 730, 5, 3, 'Room Temperature', TRUE, TRUE, FALSE, NULL, TRUE),
('MED-051', '6001234567940', 'Montelukast 10mg', 'Montelukast', 'Montelukast Sodium', 'Merck', 'UniPharm', 'Tablet', '10mg', 30, 'Tablets', 1, 'Respiratory', 'S3', TRUE, FALSE, TRUE, 89.00, 178.50, 730, 10, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-052', '6001234567941', 'Nasonex Nasal Spray', 'Mometasone', 'Mometasone Furoate', 'Merck', 'Aspen Pharmacare', 'Spray', '50mcg', 140, 'Doses', 5, 'Corticosteroid', 'S3', TRUE, FALSE, FALSE, 134.00, 268.50, 730, 10, 3, 'Room Temperature', FALSE, FALSE, TRUE, '8,9,10,11', TRUE),
('MED-053', '6001234567942', 'Riamet Tablets', 'Artemether + Lumefantrine', 'Multi-ingredient', 'Novartis', 'Imperial Health', 'Tablet', 'Combination', 24, 'Tablets', 10, 'Antimalarial', 'S4', TRUE, FALSE, FALSE, 89.00, 178.50, 730, 10, 3, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-054', '6001234567943', 'Doxycycline 100mg', 'Doxycycline', 'Doxycycline Hyclate', 'Aspen', 'Aspen Pharmacare', 'Capsule', '100mg', 50, 'Capsules', 11, 'Antibiotic', 'S4', TRUE, FALSE, TRUE, 67.00, 134.50, 730, 12, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-055', '6001234567944', 'Flagyl 400mg', 'Metronidazole', 'Metronidazole', 'Sanofi', 'Aspen Pharmacare', 'Tablet', '400mg', 21, 'Tablets', 10, 'Antibiotic', 'S3', TRUE, FALSE, FALSE, 56.00, 112.50, 730, 12, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-056', '6001234567945', 'Zinnat 250mg', 'Cefuroxime', 'Cefuroxime Axetil', 'GSK', 'Aspen Pharmacare', 'Tablet', '250mg', 14, 'Tablets', 10, 'Antibiotic', 'S4', TRUE, FALSE, FALSE, 234.00, 468.50, 730, 8, 3, 'Room Temperature', FALSE, TRUE, FALSE, NULL, TRUE),
('MED-057', '6001234567946', 'Bactrim Forte', 'Trimethoprim + Sulfamethoxazole', 'Multi-ingredient', 'Aspen', 'Aspen Pharmacare', 'Tablet', 'Combination', 20, 'Tablets', 10, 'Antibiotic', 'S4', TRUE, FALSE, FALSE, 89.00, 178.50, 730, 12, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-058', '6001234567947', 'Diflucan 150mg', 'Fluconazole', 'Fluconazole', 'Pfizer', 'Aspen Pharmacare', 'Capsule', '150mg', 1, 'Capsule', 10, 'Antifungal', 'S4', TRUE, FALSE, FALSE, 67.00, 134.50, 730, 15, 3, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-059', '6001234567948', 'Canesten Cream 1%', 'Clotrimazole', 'Clotrimazole', 'Bayer', 'UniPharm', 'Cream', '1%', 20, 'g', 8, 'Antifungal', 'S2', FALSE, FALSE, FALSE, 45.00, 89.90, 730, 20, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE),
('MED-060', '6001234567949', 'Deep Heat Rub', 'Methyl Salicylate + Menthol', 'Multi-ingredient', 'Reckitt Benckiser', 'UniPharm', 'Cream', 'Combination', 67, 'g', 7, 'Topical Analgesic', 'S0', FALSE, FALSE, FALSE, 34.00, 67.90, 730, 25, 2, 'Room Temperature', FALSE, FALSE, FALSE, NULL, TRUE);

-- Verify
SELECT COUNT(*) as medication_count FROM dwh.dim_medication;

-- Show distribution by category
SELECT 
    c.clinical_category,
    COUNT(*) as med_count
FROM dwh.dim_medication m
JOIN dwh.dim_medication_category c ON m.category_key = c.category_key
WHERE m.is_active = TRUE AND m.is_current = TRUE
GROUP BY c.clinical_category
ORDER BY med_count DESC;

-- Show top therapeutic classes
SELECT 
    therapeutic_class,
    COUNT(*) as count
FROM dwh.dim_medication
WHERE is_active = TRUE AND is_current = TRUE
GROUP BY therapeutic_class
ORDER BY count DESC
LIMIT 10;