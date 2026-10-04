-- ============================================================
-- Home360 — Phase 1: Synthetic Seed Data
-- ============================================================
-- Run after 02_schema.sql.
--
-- 12 customers, each designed to exercise a distinct NBA path:
--
--   C001  May Chen         HERO — flood-risk upgrade, premium hike,
--                          long tenure, no claims, concerned sentiment.
--                          Full renewal comparison scenario.
--
--   C002  Robert Diaz      Active open flood claim, anxious, mid-tenure.
--   C003  Linda Okafor     High churn risk, price-sensitive, short tenure.
--   C004  James Park       Low risk, happy, billing question only.
--   C005  Priya Singh      Post-fire rebuild, coverage gap concern.
--   C006  Sarah Thompson   Earthquake zone, new risk, long tenure.
--   C007  Carlos Mendez    Multiple past claims, insurer may non-renew.
--   C008  Aisha Patel      New customer, first renewal, no history.
--   C009  David Kim        High-value property, loyalty discount candidate.
--   C010  Maria Garcia     Recently moved, property transfer scenario.
--   C011  Tom Williams     Lapsed policy, win-back opportunity.
--   C012  Yuki Tanaka      Condo, HOA coverage overlap question.
--
-- May (C001) has the richest data: two policy versions, two risk
-- assessments, a multi-turn call transcript, and the perfect setup
-- for the "explain renewal + offer alternative" NBA path.
-- ============================================================

USE DATABASE HOME360_DB;
USE SCHEMA CORE;

-- ============================================================
-- CUSTOMER
-- ============================================================
INSERT INTO CUSTOMER (customer_id, name, age, tenure_years, customer_value, payment_history, churn_risk_score) VALUES
('C001', 'May Chen',         42,  6.5, 18500.00, 'EXCELLENT', 0.35),
('C002', 'Robert Diaz',      55,  3.0,  9200.00, 'GOOD',      0.40),
('C003', 'Linda Okafor',     61,  1.2,  7800.00, 'FAIR',      0.78),
('C004', 'James Park',       37,  5.0, 12300.00, 'EXCELLENT', 0.08),
('C005', 'Priya Singh',      49,  6.8, 15400.00, 'GOOD',      0.30),
('C006', 'Sarah Thompson',   58,  9.2, 22100.00, 'EXCELLENT', 0.15),
('C007', 'Carlos Mendez',    44,  4.5, 11000.00, 'FAIR',      0.55),
('C008', 'Aisha Patel',      29,  0.8,  5200.00, 'GOOD',      0.20),
('C009', 'David Kim',        52,  7.0, 31000.00, 'EXCELLENT', 0.10),
('C010', 'Maria Garcia',     35,  2.5,  8900.00, 'GOOD',      0.45),
('C011', 'Tom Williams',     63, 10.0, 19500.00, 'POOR',      0.85),
('C012', 'Yuki Tanaka',      31,  1.5,  6700.00, 'GOOD',      0.18);

-- ============================================================
-- PROPERTY
-- ============================================================
INSERT INTO PROPERTY (property_id, customer_id, property_type, location, building_age, construction_type) VALUES
('P001', 'C001', 'SINGLE_FAMILY', 'Cedar Falls, IA',      22, 'WOOD_FRAME'),
('P002', 'C002', 'SINGLE_FAMILY', 'Baton Rouge, LA',      15, 'BRICK'),
('P003', 'C003', 'TOWNHOME',      'Austin, TX',            8, 'WOOD_FRAME'),
('P004', 'C004', 'CONDO',         'Denver, CO',            5, 'CONCRETE'),
('P005', 'C005', 'SINGLE_FAMILY', 'Santa Rosa, CA',       30, 'WOOD_FRAME'),
('P006', 'C006', 'SINGLE_FAMILY', 'Portland, OR',         45, 'BRICK'),
('P007', 'C007', 'SINGLE_FAMILY', 'Mobile, AL',           28, 'WOOD_FRAME'),
('P008', 'C008', 'CONDO',         'Charlotte, NC',         3, 'CONCRETE'),
('P009', 'C009', 'SINGLE_FAMILY', 'Palo Alto, CA',        18, 'MIXED'),
('P010', 'C010', 'TOWNHOME',      'Phoenix, AZ',          12, 'BRICK'),
('P011', 'C011', 'SINGLE_FAMILY', 'Tulsa, OK',            55, 'WOOD_FRAME'),
('P012', 'C012', 'CONDO',         'Seattle, WA',           2, 'CONCRETE');

-- ============================================================
-- POLICY_VERSION
-- ============================================================
-- May (C001) has two versions: CURRENT (expiring) and RENEWAL (proposed).
-- Key differences: premium +18%, flood deductible doubled, flood coverage
-- limit reduced, new sewer-backup exclusion added.
--
-- Other customers have at least a CURRENT policy; some also have RENEWAL.
-- ============================================================

-- === May Chen (C001) — the hero scenario ===
INSERT INTO POLICY_VERSION VALUES
('POL001', 'C001', 'CURRENT', 'HOME', 'ACTIVE',
 '2025-04-01', '2026-03-31',
 8500.00,   -- annual premium
 1500.00,   -- deductible
 250000.00, -- building coverage
 75000.00,  -- contents coverage
 50000.00,  -- flood coverage
 2500.00,   -- flood deductible
 'Earthquake, intentional damage',
 '2026-03-31'),

('POL001', 'C001', 'RENEWAL', 'HOME', 'PROPOSED',
 '2026-04-01', '2027-03-31',
 10030.00,  -- annual premium (+18%)
 1500.00,   -- general deductible unchanged
 250000.00, -- building coverage unchanged
 75000.00,  -- contents coverage unchanged
 35000.00,  -- flood coverage REDUCED from 50k to 35k
 5000.00,   -- flood deductible DOUBLED from 2.5k to 5k
 'Earthquake, intentional damage, sewer backup',  -- new exclusion added
 '2027-03-31');

-- === Robert Diaz (C002) ===
INSERT INTO POLICY_VERSION VALUES
('POL002', 'C002', 'CURRENT', 'HOME', 'ACTIVE',
 '2025-01-15', '2026-01-14',
 11200.00, 2000.00, 300000.00, 40000.00, 50000.00, 3000.00,
 'Earthquake', '2026-01-14');

-- === Linda Okafor (C003) ===
INSERT INTO POLICY_VERSION VALUES
('POL003', 'C003', 'CURRENT', 'HOME', 'ACTIVE',
 '2025-11-01', '2026-10-31',
 6800.00, 2500.00, 220000.00, 30000.00, 0.00, 0.00,
 'Flood, earthquake', '2026-10-31'),

('POL003', 'C003', 'RENEWAL', 'HOME', 'PROPOSED',
 '2026-11-01', '2027-10-31',
 7500.00, 2500.00, 220000.00, 30000.00, 0.00, 0.00,
 'Flood, earthquake', '2027-10-31');

-- === James Park (C004) ===
INSERT INTO POLICY_VERSION VALUES
('POL004', 'C004', 'CURRENT', 'HOME', 'ACTIVE',
 '2025-06-20', '2026-06-19',
 5400.00, 1000.00, 180000.00, 50000.00, 50000.00, 1500.00,
 'None', '2026-06-19');

-- === Priya Singh (C005) ===
INSERT INTO POLICY_VERSION VALUES
('POL005', 'C005', 'CURRENT', 'HOME', 'ACTIVE',
 '2025-02-01', '2026-01-31',
 9800.00, 2000.00, 400000.00, 60000.00, 0.00, 0.00,
 'Flood', '2026-01-31'),

('POL005', 'C005', 'RENEWAL', 'HOME', 'PROPOSED',
 '2026-02-01', '2027-01-31',
 12500.00, 2500.00, 480000.00, 70000.00, 0.00, 0.00,
 'Flood', '2027-01-31');

-- === Sarah Thompson (C006) ===
INSERT INTO POLICY_VERSION VALUES
('POL006', 'C006', 'CURRENT', 'HOME', 'ACTIVE',
 '2025-05-01', '2026-04-30',
 7200.00, 1500.00, 280000.00, 45000.00, 25000.00, 2000.00,
 'Intentional damage', '2026-04-30'),

('POL006', 'C006', 'RENEWAL', 'HOME', 'PROPOSED',
 '2026-05-01', '2027-04-30',
 8900.00, 2000.00, 280000.00, 45000.00, 25000.00, 3000.00,
 'Intentional damage', '2027-04-30');

-- === Carlos Mendez (C007) ===
INSERT INTO POLICY_VERSION VALUES
('POL007', 'C007', 'CURRENT', 'HOME', 'ACTIVE',
 '2025-03-01', '2026-02-28',
 13500.00, 3000.00, 270000.00, 35000.00, 40000.00, 4000.00,
 'Earthquake, mold', '2026-02-28');

-- === Aisha Patel (C008) ===
INSERT INTO POLICY_VERSION VALUES
('POL008', 'C008', 'CURRENT', 'HOME', 'ACTIVE',
 '2025-12-01', '2026-11-30',
 4200.00, 1000.00, 160000.00, 40000.00, 30000.00, 1500.00,
 'Earthquake', '2026-11-30'),

('POL008', 'C008', 'RENEWAL', 'HOME', 'PROPOSED',
 '2026-12-01', '2027-11-30',
 4400.00, 1000.00, 160000.00, 40000.00, 30000.00, 1500.00,
 'Earthquake', '2027-11-30');

-- === David Kim (C009) ===
INSERT INTO POLICY_VERSION VALUES
('POL009', 'C009', 'CURRENT', 'HOME', 'ACTIVE',
 '2025-07-01', '2026-06-30',
 18500.00, 5000.00, 950000.00, 150000.00, 100000.00, 10000.00,
 'None', '2026-06-30');

-- === Maria Garcia (C010) ===
INSERT INTO POLICY_VERSION VALUES
('POL010', 'C010', 'CURRENT', 'HOME', 'ACTIVE',
 '2025-09-01', '2026-08-31',
 6100.00, 1500.00, 200000.00, 35000.00, 20000.00, 2000.00,
 'Earthquake, sewer backup', '2026-08-31');

-- === Tom Williams (C011) ===
INSERT INTO POLICY_VERSION VALUES
('POL011', 'C011', 'CURRENT', 'HOME', 'LAPSED',
 '2024-08-01', '2025-07-31',
 8900.00, 2000.00, 240000.00, 40000.00, 30000.00, 3000.00,
 'Earthquake', '2025-07-31');

-- === Yuki Tanaka (C012) ===
INSERT INTO POLICY_VERSION VALUES
('POL012', 'C012', 'CURRENT', 'HOME', 'ACTIVE',
 '2025-10-15', '2026-10-14',
 3800.00, 750.00, 120000.00, 60000.00, 15000.00, 1000.00,
 'Earthquake, named storms above Cat 3', '2026-10-14');

-- ============================================================
-- HOME_RISK_HISTORY
-- ============================================================
-- May (C001) has TWO assessments: the original (MEDIUM flood risk)
-- and the recent one (HIGH flood risk) that triggered the renewal
-- premium increase.
-- ============================================================

-- === May Chen (C001) — two assessments showing flood-risk upgrade ===
INSERT INTO HOME_RISK_HISTORY VALUES
('RA001', 'P001', '2024-03-15', 'MEDIUM', 'LOW', 'LOW', 0.42,
 'Standard risk profile. Property in FEMA Zone X (moderate flood risk). No recent flood events in immediate area.'),

('RA002', 'P001', '2026-01-20', 'HIGH', 'LOW', 'LOW', 0.78,
 'FEMA remapped Cedar Falls neighborhood to Zone AE (high-risk flood area) following 2025 watershed study. Nearby Cedar River flood-stage projections increased. Historical flood frequency in zip code rose from 1-in-100 to 1-in-50 year event.');

-- === Other customers — one assessment each ===
INSERT INTO HOME_RISK_HISTORY VALUES
('RA003', 'P002', '2025-06-10', 'HIGH', 'LOW', 'LOW', 0.82,
 'Baton Rouge location in active FEMA flood zone. Repeated regional flooding events 2023-2025.'),

('RA004', 'P003', '2025-11-01', 'LOW', 'MEDIUM', 'LOW', 0.30,
 'Austin area has moderate wildfire exposure. No significant flood or earthquake risk.'),

('RA005', 'P004', '2025-05-15', 'LOW', 'LOW', 'LOW', 0.12,
 'Denver condo in low-risk zone. Concrete construction. Minimal natural hazard exposure.'),

('RA006', 'P005', '2025-01-10', 'LOW', 'HIGH', 'MEDIUM', 0.74,
 'Santa Rosa in Sonoma County wildfire corridor. Property survived 2025 fire season but area remains high-risk. Moderate seismic exposure.'),

('RA007', 'P006', '2024-09-01', 'LOW', 'LOW', 'MEDIUM', 0.35,
 'Portland has low flood/fire risk but sits in Cascadia subduction zone. Moderate earthquake exposure.'),

('RA008', 'P006', '2026-02-15', 'LOW', 'LOW', 'HIGH', 0.62,
 'USGS updated Cascadia fault-line probability model. Portland earthquake risk upgraded to HIGH based on new 50-year event projections.'),

('RA009', 'P007', '2025-08-20', 'HIGH', 'LOW', 'LOW', 0.70,
 'Mobile, AL in hurricane flood zone. Multiple weather events in past 3 years increased risk score.'),

('RA010', 'P008', '2025-12-01', 'LOW', 'LOW', 'LOW', 0.10,
 'Charlotte condo, minimal natural hazard exposure. New construction with modern building codes.'),

('RA011', 'P009', '2025-07-01', 'LOW', 'MEDIUM', 'HIGH', 0.55,
 'Palo Alto sits on San Andreas fault system. Moderate wildfire risk from nearby hills. High property value increases exposure.'),

('RA012', 'P010', '2025-09-15', 'LOW', 'MEDIUM', 'LOW', 0.28,
 'Phoenix has minimal flood risk. Moderate wildfire risk from surrounding desert brush.'),

('RA013', 'P011', '2025-04-01', 'MEDIUM', 'LOW', 'LOW', 0.38,
 'Tulsa has moderate flood risk due to Arkansas River proximity. Older construction is a factor.'),

('RA014', 'P012', '2025-10-01', 'LOW', 'LOW', 'MEDIUM', 0.22,
 'Seattle condo in seismically active region. Modern concrete construction mitigates risk.');

-- ============================================================
-- CLAIM
-- ============================================================
-- May (C001) has ONE small, old, closed claim — demonstrating she
-- is a low-claims customer. Other customers have varied claim profiles.
-- ============================================================
INSERT INTO CLAIM (claim_id, customer_id, policy_id, claim_type, claim_status, claim_amount, claim_date) VALUES
('CLM001', 'C001', 'POL001', 'THEFT',     'CLOSED',   1800.00, '2022-11-05'),
('CLM002', 'C002', 'POL002', 'FLOOD',     'OPEN',    38000.00, '2026-09-28'),
('CLM003', 'C005', 'POL005', 'FIRE',      'CLOSED',  52000.00, '2025-10-12'),
('CLM004', 'C004', 'POL004', 'THEFT',     'CLOSED',   1200.00, '2023-04-02'),
('CLM005', 'C007', 'POL007', 'FLOOD',     'CLOSED',  15000.00, '2024-06-18'),
('CLM006', 'C007', 'POL007', 'FLOOD',     'CLOSED',  22000.00, '2025-04-30'),
('CLM007', 'C007', 'POL007', 'LIABILITY', 'CLOSED',   8500.00, '2025-09-10'),
('CLM008', 'C011', 'POL011', 'FLOOD',     'DENIED',  12000.00, '2025-05-20');

-- ============================================================
-- INTERACTION
-- ============================================================
-- May (C001) has the main hero interaction: she calls about renewal,
-- questions the price increase, and asks about coverage — exactly
-- matching the MVP scenario.
-- ============================================================

-- === May Chen (C001) — the hero call ===
INSERT INTO INTERACTION VALUES
('INT001', 'C001', 'CALL', '2026-10-03 09:14:00',
 'Agent: Thank you for calling HomeShield Insurance, this is Jordan. How can I help you today?

Customer: Hi Jordan. I''ve been insured with you for years now and I''m calling because I got my renewal letter. I want to renew my home insurance but I''m confused — why has the price increased this year? It went up quite a lot. Is my coverage still the same?

Agent: I understand your concern, May. Let me pull up your policy and the renewal details right now so we can go through everything together.

Customer: Please do. I''ve always paid on time and I haven''t made any major claims. I don''t understand why I should be paying more. If the price keeps going up I might have to look at other options.

Agent: I completely understand. Give me just a moment to review the changes and I''ll explain exactly what''s different and why.',
 NULL);

-- === Other customer interactions ===
INSERT INTO INTERACTION VALUES
('INT002', 'C002', 'CALL', '2026-10-02 16:40:00',
 'Agent: Hi Robert, I see you have an open flood claim from last week.
Customer: Yes, I''m calling to check the status. The adjuster hasn''t called me back and I''m getting anxious. My dining room floor is still torn up and I need to know when repairs can start.
Agent: I''m sorry about the delay. Let me check with the claims team and get you an update right away.',
 'Customer anxious about claim delay. Escalated to claims supervisor.');

INSERT INTO INTERACTION VALUES
('INT003', 'C003', 'CHAT', '2026-09-30 11:05:00',
 'Customer: My renewal is coming up next month and honestly I''ve been looking at quotes from other companies. Your premium went up again this year and I don''t feel like I''m getting much for it. What can you do to keep me?
Agent: I hear you, Linda. Let me see what options we have and walk through your coverage together so we can find something that works.',
 'High churn risk. Customer actively shopping competitors.');

INSERT INTO INTERACTION VALUES
('INT004', 'C004', 'EMAIL', '2026-10-01 08:22:00',
 'Subject: Question about last month''s invoice

Hi, I noticed my autopay charge was slightly higher than usual last month. Can someone explain the breakdown? Otherwise everything with the policy has been fine — no issues to report. Thanks, James',
 'Routine billing inquiry. No risk signals.');

INSERT INTO INTERACTION VALUES
('INT005', 'C005', 'CALL', '2026-09-25 14:50:00',
 'Agent: Hi Priya, thanks for holding. How can I help?
Customer: We finished rebuilding after the fire last year and I want to make sure the new structure is fully covered going forward. It cost more to rebuild than I expected — about $480,000 total. My current dwelling limit is only $400,000 and I''m worried that''s not enough anymore.
Agent: That''s a really important question. Let''s review your current dwelling limit against the actual rebuild cost.',
 'Post-fire rebuild complete. Customer requesting coverage increase to match new rebuild cost.');

INSERT INTO INTERACTION VALUES
('INT006', 'C006', 'CALL', '2026-03-10 10:30:00',
 'Agent: Good morning, Sarah. What can I help with today?
Customer: I got my renewal and the premium went up by over $1,700. The letter mentions something about earthquake risk changes but I don''t understand the details. Can you explain?
Agent: Of course. There was a recent update to the seismic risk models for your area. Let me walk you through what changed.',
 'Customer concerned about earthquake risk reclassification and premium increase.');

INSERT INTO INTERACTION VALUES
('INT007', 'C007', 'CALL', '2026-02-05 15:20:00',
 'Agent: Hi Carlos. I see your renewal is coming up at the end of the month.
Customer: Yeah, I know. Look, I''ve had a tough couple of years with the flooding. Am I going to have trouble renewing?
Agent: Let me review your account and see where things stand. I want to make sure we find the best path forward.',
 'Customer worried about non-renewal due to claims history. 3 claims in 18 months.');

INSERT INTO INTERACTION VALUES
('INT008', 'C011', 'EMAIL', '2026-09-15 09:00:00',
 'Subject: Can I get my insurance back?

Hi, my policy lapsed a couple months ago because I missed some payments during a rough patch. Things are better now and I want to get coverage again. The house is still in good shape. Is there a way to reinstate or do I need to start over? Tom Williams, Policy POL011',
 'Lapsed customer requesting reinstatement. Payment history was POOR.');
