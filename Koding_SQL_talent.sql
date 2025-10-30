-- Skrip SQL Final Match Rate dalam Format Detail (Long Format)
-- Semua Match Score (TV, TGV, Final) dibatasi Maksimal 100%

WITH BENCHMARK_CONFIG AS (
    -- Success Formula Baseline
    SELECT 
        7.0 AS papi_n_benchmark, 7.0 AS papi_z_benchmark, 6.0 AS papi_l_benchmark, 7.0 AS papi_d_benchmark,  
        110.0 AS iq_benchmark, 3.0 AS avg_comp_benchmark  
),

PAPI_SCORES_WIDE AS (
    -- Pivot skor PAPI
    SELECT employee_id,
        MAX(CASE WHEN scale_code = 'Papi_N' THEN score END) AS papi_n, 
        MAX(CASE WHEN scale_code = 'Papi_L' THEN score END) AS papi_l, 
        MAX(CASE WHEN scale_code = 'Papi_D' THEN score END) AS papi_d, 
        MAX(CASE WHEN scale_code = 'Papi_Z' THEN score END) AS papi_z
    FROM papi_scores GROUP BY employee_id
),

AVG_COMPETENCIES AS (
    -- Rata-rata skor kompetensi terbaru
    SELECT employee_id, AVG(score) AS avg_comp_score
    FROM competencies_yearly WHERE year = (SELECT MAX(year) FROM competencies_yearly)
    GROUP BY employee_id
),

RAW_MATCH_RATES AS (
    -- 1. Menghitung Match Rate TV (Wide) DAN MEMBATASI HASIL MAKSIMAL 100%
    SELECT
        e.employee_id, e.fullname, e.nip, e.years_of_service_months,
        
        -- Kolom Kunci Dimensi
        e.position_id, e.grade_id, e.directorate_id,
        
        -- Skor Mentah (user_score)
        COALESCE(ps.papi_n, 0)::numeric AS papi_n_score, COALESCE(ps.papi_z, 0)::numeric AS papi_z_score, 
        COALESCE(ps.papi_l, 0)::numeric AS papi_l_score, COALESCE(ps.papi_d, 0)::numeric AS papi_d_score, 
        COALESCE(pp.iq, 0)::numeric AS iq_score, COALESCE(ac.avg_comp_score, 0)::numeric AS comp_score,
        
        -- Baseline Score
        bc.papi_n_benchmark, bc.papi_z_benchmark, bc.papi_l_benchmark, bc.papi_d_benchmark, bc.iq_benchmark, bc.avg_comp_benchmark,
        
        -- TV Match Score (match_score) - DIBATASI 100% DENGAN LEAST()
        LEAST((COALESCE(ps.papi_n, 0)::numeric / bc.papi_n_benchmark) * 100, 100.0) AS papi_n_match,
        LEAST((COALESCE(ps.papi_z, 0)::numeric / bc.papi_z_benchmark) * 100, 100.0) AS papi_z_match,
        LEAST((COALESCE(ps.papi_l, 0)::numeric / bc.papi_l_benchmark) * 100, 100.0) AS papi_l_match,
        LEAST((COALESCE(ps.papi_d, 0)::numeric / bc.papi_d_benchmark) * 100, 100.0) AS papi_d_match,
        LEAST((COALESCE(pp.iq, 0)::numeric / bc.iq_benchmark) * 100, 100.0) AS iq_match,
        LEAST((COALESCE(ac.avg_comp_score, 0)::numeric / bc.avg_comp_benchmark) * 100, 100.0) AS comp_match
        
    FROM employees e
    LEFT JOIN PAPI_SCORES_WIDE ps ON e.employee_id = ps.employee_id
    LEFT JOIN profiles_psych pp ON e.employee_id = pp.employee_id
    LEFT JOIN AVG_COMPETENCIES ac ON e.employee_id = ac.employee_id
    CROSS JOIN BENCHMARK_CONFIG bc  
),

TGV_CALC AS (
    -- 2. Menghitung TGV Match Score. Karena TV sudah dibatasi 100%, TGV secara otomatis juga <= 100%
    SELECT
        employee_id,
        -- Drive & Achievement
        (papi_n_match + papi_z_match) / 2 AS tgv_drive_achievement,
        -- Leadership & Influence
        (papi_l_match + papi_d_match) / 2 AS tgv_leadership_influence,
        -- Cognitive Strategy
        iq_match AS tgv_cognitive_strategy,
        -- Core Competencies
        comp_match AS tgv_core_competencies
    FROM RAW_MATCH_RATES
),

FINAL_SCORE AS (
    -- 3. Menghitung Final Match Rate Weighted (Pasti <= 100%)
    SELECT 
        employee_id,
        (tgv_drive_achievement * 0.40) + (tgv_leadership_influence * 0.35) + 
        (tgv_cognitive_strategy * 0.20) + (tgv_core_competencies * 0.05) AS final_match_rate_weighted
    FROM TGV_CALC
),

TV_LONG AS (
    -- 4. UNPIVOT/UNION ALL (Menggunakan nilai TV Match Score yang sudah dibatasi 100%)
    -- Drive & Achievement
    SELECT employee_id, 'Drive & Achievement' AS tgv_name, 0.40 AS tgv_weight, 'Papi_N' AS tv_name, 
           papi_n_score AS user_score, papi_n_benchmark AS baseline_score, papi_n_match AS tv_match_score 
    FROM RAW_MATCH_RATES
    UNION ALL
    SELECT employee_id, 'Drive & Achievement' AS tgv_name, 0.40 AS tgv_weight, 'Papi_Z' AS tv_name, 
           papi_z_score AS user_score, papi_z_benchmark AS baseline_score, papi_z_match AS tv_match_score 
    FROM RAW_MATCH_RATES
    
    -- Leadership & Influence
    UNION ALL
    SELECT employee_id, 'Leadership & Influence' AS tgv_name, 0.35 AS tgv_weight, 'Papi_L' AS tv_name, 
           papi_l_score AS user_score, papi_l_benchmark AS baseline_score, papi_l_match AS tv_match_score 
    FROM RAW_MATCH_RATES
    UNION ALL
    SELECT employee_id, 'Leadership & Influence' AS tgv_name, 0.35 AS tgv_weight, 'Papi_D' AS tv_name, 
           papi_d_score AS user_score, papi_d_benchmark AS baseline_score, papi_d_match AS tv_match_score 
    FROM RAW_MATCH_RATES
    
    -- Cognitive Strategy
    UNION ALL
    SELECT employee_id, 'Cognitive Strategy' AS tgv_name, 0.20 AS tgv_weight, 'IQ' AS tv_name, 
           iq_score AS user_score, iq_benchmark AS baseline_score, iq_match AS tv_match_score 
    FROM RAW_MATCH_RATES
    
    -- Core Competencies
    UNION ALL
    SELECT employee_id, 'Core Competencies' AS tgv_name, 0.05 AS tgv_weight, 'Avg_Comp' AS tv_name, 
           comp_score AS user_score, avg_comp_benchmark AS baseline_score, comp_match AS tv_match_score 
    FROM RAW_MATCH_RATES
)

--- ## 5. FINAL SELECT
---
SELECT
    -- Kolom Identitas & Dimensi
    r.employee_id,
    r.fullname,
    r.nip,
    ddi.name AS directorate,    -- Dimensi Directorate
    dp.name AS role,            -- position_name -> role
    dg.name AS grade,           -- grade_name -> grade
    r.years_of_service_months,

    -- Kolom Detail Match Score (TV & TGV)
    tv.tgv_name,
    tv.tv_name,
    tv.baseline_score,
    tv.user_score,
    tv.tv_match_score,          -- Sekarang Maksimal 100%
    
    -- Ambil TGV Match Score dari TGV_CALC (Sekarang Maksimal 100%)
    CASE tv.tgv_name
        WHEN 'Drive & Achievement' THEN tgv.tgv_drive_achievement
        WHEN 'Leadership & Influence' THEN tgv.tgv_leadership_influence
        WHEN 'Cognitive Strategy' THEN tgv.tgv_cognitive_strategy
        WHEN 'Core Competencies' THEN tgv.tgv_core_competencies
        ELSE NULL
    END AS tgv_match_score,
    
    -- Final Match Score Weighted (Persen) - Pasti Maksimal 100%
    fs.final_match_rate_weighted AS final_weight_score 

FROM TV_LONG tv

LEFT JOIN RAW_MATCH_RATES r ON tv.employee_id = r.employee_id 
LEFT JOIN TGV_CALC tgv ON tv.employee_id = tgv.employee_id
LEFT JOIN FINAL_SCORE fs ON tv.employee_id = fs.employee_id

-- JOIN Dimensi
LEFT JOIN dim_positions dp ON r.position_id = dp.position_id
LEFT JOIN dim_grades dg ON r.grade_id = dg.grade_id
LEFT JOIN dim_directorates ddi ON r.directorate_id = ddi.directorate_id

ORDER BY r.employee_id, tv.tgv_name, tv.tv_name;