select *
from {{ ref('sales') }}
where gross_amount < 0
   or net_amount < 0
