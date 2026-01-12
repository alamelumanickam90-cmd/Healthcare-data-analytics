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
