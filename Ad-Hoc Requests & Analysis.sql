----The project addresses six business requests:


-- Business Request1: Monthly Claim Amount Drop Analysis (2019–2024)
-- Objective: Identify the top 3 months with the largest MoM decline
-- Output: city_name, month, total_claim_amount

with base AS(
 select 
	    dc.city as City_Name,
	    fp.date as Month,
	    fp.Total_Claim_Amount,
	    lag(fp.Total_Claim_Amount)over (PARTITION by dc.city_id order by fp.date asc) as Prev_Total_Claim_Amount
	from fact_claims fp
	join dim_city dc
	on fp.city_id = dc.city_id
	),
decline as
(
select
  	 City_Name,
	   Month,
	   Total_Claim_Amount,
	   Prev_Total_Claim_Amount,
	   (Total_Claim_Amount-Prev_Total_Claim_Amount) as Month_Change 
from base
)
select
  	City_Name,
	  Month,
	  Total_Claim_Amount,
	  Prev_Total_Claim_Amount,
	  Month_Change
from decline
where Month_Change < 0
order by Month_Change asc
limit 3;

City_Name 	Month 	Total_Claim_Amount 	Prev_Total_Claim_Amount 	Month_Change
Varanasi	2021-01		382018				441825						-59807
Varanasi	2019-11		431606				487255						-55649
jaipur		2020-01		420680				472538						-51858


-- Business Request2: Identify procedure categories that contributed more than 50% of total yearly healthcare revenue.
-- Fields Requiredyear, category_name, procedure_revenue, total_revenue_year, pct_of_year_total
SELECT 
    t.year,
    t.category_id,
    d.procedure_category AS procedure_category,
    t.procedure_revenue,
    t.total_revenue,
    (t.procedure_revenue / t.total_revenue) * 100 AS per_of_year_total
FROM (
    SELECT 
        RIGHT(Quarter_New,4) AS year,
        category_id,
        SUM(procedure_revenue) AS procedure_revenue,
        SUM(SUM(procedure_revenue)) OVER (PARTITION BY RIGHT(Quarter_New,4)) AS total_revenue
    FROM fact_procedure_revenue
    GROUP BY 
        category_id,
        RIGHT(Quarter_New,4)
) AS t
JOIN dim_procedure_category d
    ON t.category_id = d.category_id
    WHERE (t.procedure_revenue / t.total_revenue) > 0.5
   ORDER BY 
    t.year,
    d.category_id;
    
Output:
year	category_id	procedure_category	procedure_revenue	total_revenue	per_of_year_total

 Business Request 3: Claim Approval Efficiency Leaderboard
-- Objective: Rank healthcare providers by claim approval efficiency
-- Definition: approval_efficiency = claims_approved / claims_submitted
-- Assumption: claims_approved = claims_submitted - claims_denied
-- Scope: All available claim data (no year filter applied)
-- Output:
--   provider_name (city)
--   claims_submitted
--   claims_approved
--   approval_efficiency_ratio
--   approval_efficiency_rank

-- Business Request 3: Claim Approval Efficiency Leaderboard (2024)
-- Definition: approval_efficiency = claims_approved / claims_submitted
-- Output: provider_name (city), claims_submitted_2024, claims_approved_2024,
--         approval_efficiency_ratio, approval_efficiency_rank_2024

WITH base AS (
    SELECT 
        d.city AS provider_name,
        SUM(f.claims_submitted) AS claims_submitted,
        SUM(f.claims_denied) AS claims_denied
    FROM fact_claims f
    JOIN dim_city d
        ON f.city_id = d.city_id

    GROUP BY d.city
),
calculated AS (
    SELECT
        provider_name,
        claims_submitted,
        (claims_submitted - claims_denied) AS claims_approved,
        ROUND(
            (claims_submitted - claims_denied) / claims_submitted,
            4
        ) AS approval_efficiency_ratio
    FROM base
),
ranked AS (
    SELECT
        *,
        RANK() OVER (ORDER BY approval_efficiency_ratio DESC) 
            AS approval_efficiency_rank
    FROM calculated
)
SELECT
    provider_name,
    claims_submitted,
    claims_approved,
    approval_efficiency_ratio,
    approval_efficiency_rank
FROM ranked
WHERE approval_efficiency_rank <= 5
ORDER BY approval_efficiency_rank;
provider_name	claims_submitted	claims_approved	approval_efficiency_ratio	approval_efficiency_rank
ranchi				15542659			14740028			0.9484						1
jaipur				30621736			29032754			0.9481						2
kanpur				24020911			22759261			0.9475						3
Mumbai				26367469			24961046			0.9467						4
bhopal				17929108			16969882			0.9465						5

--Business Request 4:compute the change in healthcare access rate from Q1 2021 to Q4 2021 and identify the city with the highest improvement.

Healthcare Metric Definition

Healthcare Access Rate = percentage of population with reliable access to healthcare services (insurance coverage / digital health access 
/ primary care availability)

Fields Required

city_name

healthcare_access_rate_q1_2021

healthcare_access_rate_q4_2021

delta_healthcare_access_rate

(healthcare_access_rate_q4_2021 − healthcare_access_rate_q1_2021)


with base as(
SELECT d.city as city,
       MAX(CASE WHEN f.quarter = '2021-Q1' THEN healthcare_access_rate END) AS healthcare_access_rate_q1_2021,
       MAX(CASE WHEN f.quarter = '2021-Q4' THEN healthcare_access_rate END) AS healthcare_access_rate_q4_2021
FROM fact_city_readiness f
join dim_city d on f.city_id=d.city_id
WHERE quarter LIKE '2021-%'
group by city
),
second as (
select city as City_Name,
		healthcare_access_rate_q1_2021,
        healthcare_access_rate_q4_2021,
        (healthcare_access_rate_q4_2021 - healthcare_access_rate_q1_2021) as delta_healthcare_access_rate
from base)
select * from second order by delta_healthcare_access_rate desc limit 1

	Output:
City_Name	healthcare_access_rate_q1_2021	healthcare_access_rate_q4_2021	delta_healthcare_access_rate
kanpur					74.27							76.77							2.5


-- Business Request 5: Year-over-Year Decline in Healthcare Claims & Revenue
-- Objective: Identify city-year combinations where both claim amount and procedure revenue declined compared to the previous year
-- Output: city_name, year, yearly_claims_submitted, yearly_procedure_revenue, is_declining_claims, is_declining_revenue, is_declining_both


WITH yearly_print AS (
    SELECT
        d.city as City_name,
        r.year,
        SUM(f.total_claim_amount) AS yearly_claims_submitted,
        sum(r.procedure_revenue) As Yearly_procedure_revenue
	FROM fact_claims f
    JOIN dim_city d
        ON d.city_id = f.City_id
	JOIN fact_procedure_revenue r
		ON f.claim_id = r.claim_id
        and r.year = f.year
    GROUP BY
        d.City,
        r.year order by city_name
),
comparisons AS (
    SELECT
        City_name,
        year,
        yearly_claims_submitted,
        yearly_procedure_revenue,
        LAG(yearly_claims_submitted)
            OVER (PARTITION BY City_name ORDER BY year) AS prev_net_print,
		LAG(yearly_procedure_revenue)
            OVER (PARTITION BY City_name ORDER BY year) AS prev_ad_revenue
    FROM yearly_print
)
    SELECT
        City_name,
        year,
        yearly_claims_submitted,
        yearly_procedure_revenue,
        CASE 
        WHEN SUM(CASE WHEN yearly_claims_submitted < prev_net_print THEN 1 ELSE 0 END) 
             = COUNT(prev_net_print) 
        THEN 'Yes' ELSE 'No' 
    END AS is_declining_print,
    CASE 
        WHEN SUM(CASE WHEN yearly_procedure_revenue < prev_ad_revenue THEN 1 ELSE 0 END) 
             = COUNT(prev_ad_revenue) 
        THEN 'Yes' ELSE 'No' 
    END AS is_declining_ad_revenue,
    CASE 
        WHEN SUM(CASE WHEN yearly_claims_submitted < prev_net_print THEN 1 ELSE 0 END) 
             = COUNT(prev_net_print)
         AND SUM(CASE WHEN yearly_procedure_revenue < prev_ad_revenue THEN 1 ELSE 0 END) 
             = COUNT(prev_ad_revenue)
        THEN 'Yes' ELSE 'No' 
    END AS is_declining_both from comparisons GROUP BY city_name, year,
    yearly_claims_submitted,
    yearly_procedure_revenue;

Output:
City_name	year	yearly_claims_submitted	yearly_procedure_revenue	is_declining_print	is_declining_ad_revenue	is_declining_both
Ahmedabad	2019	43494492	307430817	Yes	Yes	Yes
Ahmedabad	2020	41461608	374394653.9	Yes	No	No
Ahmedabad	2021	39770340	251244726.5	Yes	Yes	Yes
Ahmedabad	2022	37318668	426110367	Yes	No	No
Ahmedabad	2023	34863636	270999322.8	Yes	Yes	Yes
Ahmedabad	2024	32960292	375280122.2	Yes	No	No
bhopal	2019	39218472	364844045.2	Yes	Yes	Yes
bhopal	2020	36572700	289458035.2	Yes	Yes	Yes
bhopal	2021	35102460	310963659.6	Yes	No	No
bhopal	2022	32779176	475838874.1	Yes	No	No
bhopal	2023	30942972	347732382.8	Yes	Yes	Yes
bhopal	2024	29022804	328559757.7	Yes	Yes	Yes
Delhi	2019	52251096	342033235.7	Yes	Yes	Yes
Delhi	2020	49888428	289209717.5	Yes	Yes	Yes
Delhi	2021	46856028	319653272.3	Yes	No	No
Delhi	2022	44477472	511158504	Yes	No	No
Delhi	2023	41363628	330013577.5	Yes	Yes	Yes
Delhi	2024	39024120	222458639.6	Yes	Yes	Yes
jaipur	2019	67071420	243381851.3	Yes	Yes	Yes
jaipur	2020	62584164	169278845	Yes	Yes	Yes
jaipur	2021	59268336	326983253.3	Yes	No	No
jaipur	2022	56718288	165908858.6	Yes	Yes	Yes
jaipur	2023	53207148	362335423.2	Yes	No	No
jaipur	2024	49543692	368955851.8	Yes	No	No
kanpur	2019	52149336	330409872.4	Yes	Yes	Yes
kanpur	2020	49958856	213713624.2	Yes	Yes	Yes
kanpur	2021	46893552	333425358.8	Yes	No	No
kanpur	2022	44095824	362735201	Yes	No	No
kanpur	2023	41011416	274277842.3	Yes	Yes	Yes
kanpur	2024	39002148	304248089.2	Yes	No	No
lucknow	2019	28033860	365749531.4	Yes	Yes	Yes
lucknow	2020	26809176	393840432	Yes	No	No
lucknow	2021	25390524	301512742.4	Yes	Yes	Yes
lucknow	2022	24043908	267129162.1	Yes	Yes	Yes
lucknow	2023	22564080	359976132.6	Yes	No	No
lucknow	2024	21159072	341602125.1	Yes	Yes	Yes
Mumbai	2019	56913276	365772015	Yes	Yes	Yes
Mumbai	2020	54720888	273665765.4	Yes	Yes	Yes
Mumbai	2021	51469896	176078669	Yes	Yes	Yes
Mumbai	2022	48090696	316649047.3	Yes	No	No
Mumbai	2023	45507048	355588878.4	Yes	No	No
Mumbai	2024	42830748	302573959.4	Yes	Yes	Yes
Patna	2019	36242772	484210032	Yes	Yes	Yes
Patna	2020	34027296	308188532.6	Yes	Yes	Yes
Patna	2021	32466852	351918610.1	Yes	No	No
Patna	2022	30447636	318980368.9	Yes	Yes	Yes
Patna	2023	28828644	372293558.2	Yes	No	No
Patna	2024	27033828	468527847.2	Yes	No	No
ranchi	2019	33309540	327661329.1	Yes	Yes	Yes
ranchi	2020	32384076	334096799.2	Yes	No	No
ranchi	2021	30844332	263318260	Yes	Yes	Yes
ranchi	2022	28348728	312968879.9	Yes	No	No
ranchi	2023	26888916	284235773.9	Yes	Yes	Yes
ranchi	2024	25104744	336989274.8	Yes	No	No
Varanasi	2019	66373728	162624145.3	Yes	Yes	Yes
Varanasi	2020	62394900	291635030.9	Yes	No	No
Varanasi	2021	57796368	215904674	Yes	Yes	Yes
Varanasi	2022	55953420	241497080.9	Yes	No	No
Varanasi	2023	53557908	368141818	Yes	No	No
Varanasi	2024	49483332	341248131.2	Yes	Yes	Yes

-- Business Request 6: Digital Health Readiness vs Patient Engagement Outlier (2021)
-- Objective: Identify cities with high digital health readiness but low patient engagement in a digital healthcare pilot
-- Output: city_name, digital_health_readiness_score_2021, patient_engagement_metric_2021, readiness_rank_desc, engagement_rank_asc, is_digital_health_outlier

WITH readiness AS (
    SELECT 
        c.city,
        round(AVG(cr.health_insurance_coverage_rate + cr.telemedicine_adoption_rate + cr.healthcare_access_rate)/3,2)
        AS digital_health_readiness_score
    FROM fact_city_readiness cr
    JOIN dim_city c ON cr.city_id = c.city_id
    WHERE cr.year = 2021
    GROUP BY c.city
),
engagement AS (
    SELECT 
        c.city,
        COALESCE(SUM(dp.digital_health_accesses),0) AS patient_engagement_metric
    FROM fact_digital_pilot dp
    JOIN dim_city c ON c.city_id = dp.city_id
   
    GROUP BY c.city
)
SELECT 
    r.city,
    r.digital_health_readiness_score,
    e.patient_engagement_metric,
    RANK() OVER (ORDER BY r.digital_health_readiness_score DESC) AS digital_health_readiness_rank_desc,
    RANK() OVER (ORDER BY e.patient_engagement_metric ASC) AS engagement_rank_asc,
    CASE 
       WHEN RANK() OVER (ORDER BY r.digital_health_readiness_score DESC) = 1
        AND RANK() OVER (ORDER BY e.patient_engagement_metric ASC) <= 3 
       THEN 'Yes' ELSE 'No' END AS is_digital_health_outlier
FROM readiness r
JOIN engagement e ON r.city = e.city;

city	digital_health_readiness_score	patient_engagement_metric	digital_health_readiness_rank_desc	engagement_rank_asc	is_digital_health_outlier
kanpur	75.23	36289	1	1	Yes
ranchi	68.64	38686	7	2	No
Patna	70.77	62390	6	3	No
jaipur	54.95	63067	10	4	No
Mumbai	68.33	73519	8	5	No
Delhi	56.08	77378	9	6	No
Ahmedabad	72.39	82731	5	7	No
Varanasi	73.89	82763	2	8	No
lucknow	73.2	82903	4	9	No
bhopal	73.21	83111	3	10	No
