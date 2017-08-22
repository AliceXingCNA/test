select * from ap_crm.rbp_add_mcl;
select * from ap_crm.crm_analy_1st_loan;
--------add a line for testing
----------------------------------------------------------------------------------------------------------
;
with Offers as
(
select /*+materialize*/
rbp.skp_client,
rbp.skp_campaign,
rbp.dtime_campaign_valid_from,
rbp.dtime_campaign_valid_to,
rbp.CODE_OFFER_TYPE,
rbp.code_risk_grade,
rbp.amt_global_limit,
rbp.AMT_MAX_AFFORDABLE_ANNUITY,
rbp.code_xcl_pilot
from ap_crm.rbp_add_mcl rbp
where rbp.dtime_campaign_valid_from = date'2017-08-14'
and rbp.code_xcl_pilot <> '008_MOB4'
),

First_loan as
(
select /*+materialize*/
 ofs.skp_client,
 ofs.skp_campaign,
 ofs.dtime_campaign_valid_from,
 ofs.dtime_campaign_valid_to,
 ofs.code_offer_type,
 ofs.code_risk_grade,
 ofs.amt_global_limit,
 ofs.AMT_MAX_AFFORDABLE_ANNUITY,
 case
   when (ps.name_product_set
        like 'F\_APZERO\_%' escape
         '\' or ps.name_product_set in ('F_SPL_APZERO_0DP')) then
    'Zero'
   when (ps.name_product_set in ('F_1%_OP_ALL',
                                 'F_1%_OP_KA',
                                 'F_RPL_1%_OP',
                                 'F_1%_OP_STU',
                                 'Z_1%_OP_ALL',
                                 'Z_1%_OP_KA',
                                 '1%_OP_ALL',
                                 '1%_OP_KA' 
                                 ) and a.cnt_instalment_application > 12)
    then
    '1%_OP_above_12'
   when (ps.name_product_set in ('F_1%_OP_ALL',
                                 'F_1%_OP_KA',
                                 'F_RPL_1%_OP',
                                 'F_1%_OP_STU',
                                 'Z_1%_OP_ALL',
                                 'Z_1%_OP_KA',
                                 '1%_OP_ALL',
                                 '1%_OP_KA'
                                 ) and a.cnt_instalment_application <= 12)
    then
    '1%_OP_below_12'
   when
    (a.cnt_instalment_application = 10 and
    (p.RATE_INTEREST_EFFECTIVE = 0.23556 or
    p.RATE_INTEREST_EFFECTIVE = 0.26411)) then
    '10_10_10'
   when ps.NAME_PRODUCT_SET in ('F_MBT',
                                'F_MOT',
                                'F_COMP',
                                'F_BWT',
                                'F_TENTH12M_HA',
                                'F_TENTH10M_20HA',
                                'F_FUR',
                                'F_DRV',
                                'F_WED',
                                'F_EDU',
                                'F_BEA') then
    'Standard'
   when a.skp_product_channel = 3 and
        cch.name_credit_acquisition_chn_en = 'EXTREME' then
    'POS_Online'
   when a.skp_product_channel = 2 and
        cch.name_credit_acquisition_chn_en = 'EXTREME' then
    'MCL'
   else
    'Others'
 end Prod_Set
 --a.date_decision
  from Offers ofs
  join ap_crm.crm_analy_1st_loan a
  on a.skp_client = ofs.skp_client
  join owner_dwh.f_product_2_product_set_at pss
    on a.skp_product = pss.SKP_PRODUCT
   and a.date_decision between trunc(pss.DTIME_VALID_FROM) and
       trunc(pss.DTIME_VALID_TO)
   and pss.DTIME_VALID_FROM < pss.DTIME_VALID_TO - 5 -- exclude the testing product_set: 'F_MBT_LTTEST_0821'
   and pss.FLAG_DELETED = 'N'
  join owner_dwh.dc_product_set ps
    on pss.SKP_PRODUCT_SET = ps.SKP_PRODUCT_SET
   and ps.FLAG_DELETED = 'N'
   and a.date_decision between ps.DTIME_PRODUCT_SET_VALID_FROM and
       ps.DTIME_PRODUCT_SET_VALID_TO
  join owner_dwh.f_product_interest_rate_at p
    on a.skp_product = p.SKP_PRODUCT
   and a.dtime_proposal between p.DTIME_SOURCE_VALID_FROM and
       p.DTIME_SOURCE_VALID_TO
   and p.FLAG_DELETED = 'N'
  join owner_dwh.dc_credit_case cc
    on a.skp_credit_case = cc.SKP_CREDIT_CASE
  join owner_dwh.cl_credit_acquisition_chnl cch
    on cc.SKP_CREDIT_ACQUISITION_CHNL = cch.skp_credit_acquisition_chnl
)
,

Offers_all as
(
select 
rbp.skp_client,
rbp.skp_campaign,
rbp.dtime_campaign_valid_from,
rbp.dtime_campaign_valid_to,
rbp.CODE_OFFER_TYPE,
rbp.code_risk_grade,
rbp.AMT_GLOBAL_LIMIT,
rbp.AMT_MAX_AFFORDABLE_ANNUITY,
'008_MOB4' as PROD_SET
from ap_crm.rbp_add_mcl rbp
where rbp.code_xcl_pilot = '008_MOB4' 
and rbp.dtime_campaign_valid_from = date'2017-08-14'

union all

select
fl.skp_client,
fl.skp_campaign,
fl.dtime_campaign_valid_from,
fl.dtime_campaign_valid_to,
fl.code_offer_type,
fl.code_risk_grade,
fl.amt_global_limit,
fl.AMT_MAX_AFFORDABLE_ANNUITY,
fl.PROD_SET
from 
First_Loan fl

),

LEADS
AS
(
SELECT /*+materialize*/
L.SKP_CLIENT,
L.SKP_CAMPAIGN,
COUNT(DISTINCT L.SKF_XCL_LEAD) LEADS

FROM OFFERS_all OS
JOIN OWNER_DWH.F_XCL_LEAD_TT L
ON OS.SKP_CLIENT=L.SKP_CLIENT
AND OS.SKP_CAMPAIGN=L.SKP_CAMPAIGN
AND L.flag_current='Y'
AND L.FLAG_DELETED<>'Y'
AND L.SKP_SALESROOM <>-1
AND L.DTIME_ACTIVITY_END BETWEEN OS.DTIME_CAMPAIGN_VALID_FROM AND OS.DTIME_CAMPAIGN_VALID_TO 
and L.dtime_activity_end >= date '2017-08-14'
GROUP BY
L.SKP_CLIENT,
L.SKP_CAMPAIGN
)
,
ap 
as
(
SELECT /*+materialize*/
 o.skp_client,
 o.skp_campaign,
 APPL.DTIME_PROPOSAL,
 APPL.DATE_PROPOSAL,
 APPL.SKP_CREDIT_CASE,
 APPL.SKP_CREDIT_STATUS,
 APPL.SKP_APPLICATION,
 APPL.SKP_PRODUCT,
 APPL.CNT_INSTALMENT
  FROM owner_dwh.f_application_tt appl
  join offers_all o
    on appl.skp_client = o.skp_client
   and appl.DTIME_PROPOSAL between o.dtime_campaign_valid_from and
       o.dtime_campaign_valid_to
 WHERE appl.SKP_CREDIT_TYPE = 2
   and appl.SKP_PRODUCT_CHANNEL  IN (1,201)
   and appl.DTIME_PROPOSAL >= date '2017-08-14'

),

sales
as
(
select --AP.SKF_CAMPAIGN_CLIENT,
       
       AP.skp_client,
       ap.skp_campaign,
       AP.DATE_PROPOSAL,
       AP.skp_application,
       AP.SKP_CREDIT_STATUS as status_appl,
       con.skp_contract,
       con.date_decision,
       --con.skp_credit_status as status_con,
       con.amt_credit,
       CON.amt_application_annuity,
       AP.CNT_INSTALMENT                 as tenure,
       pi.RATE_INTEREST_EFFECTIVE        as EIR,
       CON.flag_early_repaid_wo_interest AS FLAG_ER15,
       CON.flag_early_repaid_w_interest  AS FLAG_ER,
       
       case
         when ins.SKP_INSURANCE is not null then
          1
         else
          0
       end flag_ins,
       case
         when fp.SKP_CREDIT_CASE is not null then
          1
         else
          0
       end flag_fp

  from AP
  left join owner_dwh.f_contract_ad con
    on AP.skp_credit_case = con.skp_credit_case
   AND CON.skp_credit_status IN (2, 3, 5, 9)

  left join owner_dwh.dc_insurance ins
    on con.skp_credit_case = ins.SKP_CREDIT_CASE
   and ins.SKP_INSURANCE_STATUS = 4
  left join owner_dwh.f_credit_service_package_tt fp
    on con.skp_credit_case = fp.SKP_CREDIT_CASE
   and fp.SKP_SERVICE_PACKAGE = 1
  left join owner_dwh.f_product_interest_rate_at pi
    on con.SKP_PRODUCT = pi.SKP_PRODUCT
   and con.DTIME_PROPOSAL between pi.DTIME_SOURCE_VALID_FROM and
       pi.DTIME_SOURCE_VALID_TO
   and con.dtime_proposal >= date '2017-08-14'

),

CONTACT
AS
(

SELECT OPS.SKP_CLIENT,
       OPS.SKP_CAMPAIGN,
       SUM(CASE
             WHEN OPS.CNT_ATTEMPT > 0 THEN
              1
             ELSE
              0
           END) FLAG_CALLED,
       SUM(CASE
             WHEN OPS.SKP_CALL_RESULT_TYPE IN (1, 34, 37) AND
                  OPS.CNT_ATTEMPT > 0 THEN
              1
             ELSE
              0
           END) FLAG_REACHED
  FROM OWNER_DWH.F_CALL_RESULT_OPS_TD OPS
  JOIN OFFERS_all O2
    ON OPS.SKP_CLIENT = O2.SKP_CLIENT
   AND OPS.SKP_CAMPAIGN = O2.SKP_CAMPAIGN
   AND OPS.DATE_CALL_LIST BETWEEN O2.DTIME_CAMPAIGN_VALID_FROM AND
       O2.DTIME_CAMPAIGN_VALID_TO
   and OPS.date_call_list >= date'2017-08-14'
 GROUP BY OPS.SKP_CLIENT, OPS.SKP_CAMPAIGN

),
INBOUND-- AT LEAST ONCE INBOUND DURING CAMPAIGN VALID PERIOD
AS
(
SELECT /*+materialize*/
 TT.SKP_CLIENT, O6.SKP_CAMPAIGN,COUNT(DISTINCT TT.SKF_CALL_DETAIL) NUM_IB

  FROM OWNER_DWH.F_CALL_DETAIL_TT TT
  JOIN offers_all O6
    ON TT.SKP_CLIENT = O6.SKP_CLIENT
   AND TT.DTIME_CALL_START BETWEEN O6.DTIME_CAMPAIGN_VALID_FROM AND
       O6.DTIME_CAMPAIGN_VALID_TO
   AND TT.SKP_CALL_DIRECTION = 5 --INBOUND CALLS
   AND (SUBSTR(TT.CODE_CALL_AGENT, 1, 2) IN ('24', '34', '44', '74') OR
       SUBSTR(TT.CODE_CALL_AGENT, 1, 1) = '9') -- INBOUND HANDLED BY TELESALES
   and TT.DTIME_CALL_START >= date'2017-08-14'
 GROUP BY TT.SKP_CLIENT, O6.SKP_CAMPAIGN

)

,
dat
as
(

select o.skp_client,
       o.dtime_campaign_valid_from,
       o.code_risk_grade,
       o.code_offer_type,
       o.PROD_SET,
       o.amt_global_limit as AMT_LIMIT,
       O.AMT_MAX_AFFORDABLE_ANNUITY as AMT_ANNUITY_LIMIT,
       CASE WHEN CT.SKP_CLIENT IS NOT NULL THEN 'IN_CALLIST' ELSE 'NON_CALLIST' END FLAG_CALLIST,
       --CASE WHEN O.CAMP_TYPE='MCL' THEN o.amt_limit ELSE 0 END AMT_LIMIT,
       --CASE WHEN O.CAMP_TYPE='MCL' THEN O.AMT_ANNUITY_LIMIT ELSE 0 END AMT_ANNUITY_LIMIT,
       CT.SKP_CLIENT AS CLIENT_CALLLIST,
       CASE
         WHEN CT.FLAG_CALLED>0 THEN CT.SKP_CLIENT ELSE NULL
       END CLIENT_CALLED,
       CASE WHEN CT.FLAG_REACHED>0 THEN CT.SKP_CLIENT ELSE NULL END CLIENT_REACHED,
       s.skp_application,
       s.status_appl,
       s.skp_contract,
       s.date_proposal,
       case when trunc(sysdate)-s.date_decision <=15 then 'N' else 'Y' end flag_15Day,
       s.amt_credit,
       S.AMT_APPLICATION_ANNUITY,
       s.tenure,
       s.eir,
       s.flag_ins,
       s.flag_fp,
       s.flag_er15,
       s.flag_er,
       L2.SKP_CLIENT AS CLIENT_LEAD,
       CASE WHEN IB.NUM_IB>0 THEN IB.SKP_CLIENT END AS CLIENT_IB
  from offers_all o
  LEFT JOIN LEADS L2
  ON O.SKP_CLIENT=L2.SKP_CLIENT
  AND O.SKP_CAMPAIGN=L2.SKP_CAMPAIGN
  
  LEFT JOIN CONTACT CT
  ON O.SKP_CLIENT=CT.SKP_CLIENT
  AND O.SKP_CAMPAIGN=CT.SKP_CAMPAIGN

  left join sales s
    on --o.skF_CAMPAIGN_client = s.skF_CAMPAIGN_client
       o.skp_client = s.skp_client
   and o.skp_campaign = s.skp_campaign
   and s.date_proposal between o.dtime_campaign_valid_from and
       o.dtime_campaign_valid_to
LEFT JOIN INBOUND IB
ON O.SKP_CLIENT=IB.SKP_CLIENT
AND O.SKP_CAMPAIGN=IB.SKP_CAMPAIGN

)


select dat.dtime_campaign_valid_from,
       dat.code_offer_type,
       dat.code_risk_grade,
       dat.PROD_SET£¬
       --DAT.FLAG_MA,
       --DAT.FLAG_LOW,
       DAT.FLAG_CALLIST, 
       trunc(Dat.date_proposal,'iw') week_proposal,
       --dat.flag_15Day, ------------------------------------------
       count(distinct dat.skp_client) CAMP_CLNS,
       /*COUNT(DISTINCT CASE
         WHEN DAT.CAMP_TYPE = 'MCL' gTHEN
          DAT.SKP_CLIENT
       END) OFFER_PILOT,*/
       COUNT(DISTINCT DAT.CLIENT_CALLLIST) CALL_LIST_CLNS,
       COUNT(DISTINCT CASE WHEN DAT.CLIENT_CALLLIST IS NULL THEN DAT.CLIENT_IB END) AS NOT_CALLIST_IB_CLNS,
       COUNT(DISTINCT DAT.CLIENT_CALLED) CALLED_CLNS,
       COUNT(DISTINCT DAT.CLIENT_REACHED) REACHED_CLNS,
       COUNT(DISTINCT CASE
               WHEN DAT.SKP_APPLICATION IS NOT NULL THEN
                DAT.SKP_CLIENT
             END) APPLICATION_CLNS,
       count(distinct dat.skp_application) NUM_APPLICATION,
       COUNT(DISTINCT CASE
               WHEN DAT.STATUS_APPL = 6 THEN
                DAT.SKP_APPLICATION
             END) NUM_APPROVED_APPLICATION,
       count(distinct dat.skp_contract) NUM_CONTRACTS,
       count(distinct case when dat.flag_15Day = 'Y' 
               then dat.skp_contract end) num_contract_15day,--------------------cnt_contract_15day
       sum(dat.flag_ins) NUM_W_INS,
       sum(dat.flag_fp) NUM_W_FLEX,
       sum(dat.amt_credit) VOLUME,
       ---sum(dat.amt_limit) vol_limit
       SUM(CASE
             WHEN DAT.SKP_CONTRACT IS NOT NULL THEN
              DAT.AMT_LIMIT
           END) VOL_LIMIT,
       --SUM(DAT.AMT_ANNUITY_LIMIT) ANNUITY_LIMIT,
       SUM(CASE
             WHEN DAT.SKP_CONTRACT IS NOT NULL THEN
              DAT.AMT_ANNUITY_LIMIT
           END) ANNUITY_LIMIT,
       SUM(DAT.AMT_APPLICATION_ANNUITY) ANNUITY_APPLICATION,
       sum(dat.amt_credit * dat.tenure) TENURE_UP,
       sum(dat.amt_credit * dat.tenure * dat.EIR) EIR_UP,
       count(distinct case
               when dat.flag_er15 = 'Y' then
                dat.skp_contract
             end) NUM_ER15,
       count(distinct case
               when dat.flag_er15 = 'Y' and dat.flag_15day ='Y' then
                dat.skp_contract
             end) NUM_ER15_15day,----------------------------------------cnt_ER15_15day
       count(distinct case
               when dat.flag_er = 'Y' then
                dat.skp_contract
             end) NUM_ER,
       COUNT(DISTINCT DAT.CLIENT_LEAD) AS LEAD_CLNS

  from dat
  
 group by dat.dtime_campaign_valid_from,
          dat.code_risk_grade,
          dat.code_offer_type,
          dat.PROD_SET,
          --DAT.FLAG_MA,
          --DAT.FLAG_LOW,
          DAT.FLAG_CALLIST,
          trunc(Dat.date_proposal,'iw')
          ;





