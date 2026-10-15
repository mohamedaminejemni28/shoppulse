const api=async path=>{const response=await fetch(`/api${path}`);if(!response.ok)throw new Error(`API ${response.status}`);return response.json()};
const money=(value,currency='USD')=>new Intl.NumberFormat('fr-FR',{style:'currency',currency,maximumFractionDigits:0}).format(Number(value||0));
const date=value=>value?new Intl.DateTimeFormat('fr-FR',{dateStyle:'medium',timeStyle:'short'}).format(new Date(value)):'—';
const esc=value=>String(value??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const badge=value=>`<span class="badge ${esc(value)}">${esc(String(value).replaceAll('_',' '))}</span>`;
const toast=message=>{const el=document.querySelector('#toast');el.textContent=message;el.classList.add('show');setTimeout(()=>el.classList.remove('show'),2200)};
const table=(headers,rows)=>`<div class="table-wrap"><table><thead><tr>${headers.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div>`;

function ordersTable(items){return table(['Commande','Client','Statut','Articles','Montant','Date'],items.map(o=>`<tr><td><strong>${esc(o.order_number)}</strong></td><td class="customer-cell"><strong>${esc(o.customer_name)}</strong><small>${esc(o.email)}</small></td><td>${badge(o.order_status)}</td><td>${o.item_count}</td><td class="money">${money(o.total_amount,o.currency)}</td><td>${date(o.ordered_at)}</td></tr>`))}

async function loadDashboard(){
  const [data,orders,products,customers,conversion,events]=await Promise.all([api('/dashboard'),api('/orders?limit=8'),api('/analytics/products?limit=5'),api('/analytics/customers?limit=5'),api('/analytics/conversion?days=30'),api('/events/recent?limit=8')]);
  const s=data.summary;
  const cards=[['Chiffre d’affaires',money(s.revenue),'$','Commandes validées'],['Commandes',s.orders,'↗',`${s.paid_order_rate}% validées`],['Panier moyen',money(s.average_order_value),'◇',`${s.active_products} produits actifs`],['Taux de conversion',`${s.conversion_rate}%`,'◎',`${s.customers} clients`]];
  document.querySelector('#metrics').innerHTML=cards.map(c=>`<article class="metric"><div class="metric-top"><span>${c[0]}</span><span class="metric-icon">${c[2]}</span></div><div class="metric-value">${c[1]}</div><div class="metric-note">${c[3]}</div></article>`).join('');
  const max=Math.max(...data.daily_sales.map(d=>Number(d.net_revenue)),1);
  document.querySelector('#sales-chart').innerHTML=data.daily_sales.map(d=>`<div class="bar-wrap" title="${money(d.net_revenue)}"><div class="bar" style="height:${Math.max(4,Number(d.net_revenue)/max*100)}%"></div><span class="bar-label">${String(d.order_date).slice(5)}</span></div>`).join('')||'<p class="empty">Aucune vente</p>';
  const maxStatus=Math.max(...data.order_statuses.map(x=>Number(x.total)),1);
  document.querySelector('#status-list').innerHTML=data.order_statuses.map(x=>`<div class="status-row"><span>${esc(x.status)}</span><div class="track"><div class="fill" style="width:${Number(x.total)/maxStatus*100}%"></div></div><strong>${x.total}</strong></div>`).join('');
  document.querySelector('#recent-orders').innerHTML=ordersTable(orders.items);
  document.querySelector('#top-products').innerHTML=table(['Produit','Ventes','Revenu'],products.map(p=>`<tr><td><strong>${esc(p.product_name)}</strong><small class="sub">${esc(p.category_name)}</small></td><td>${p.units_sold}</td><td class="money">${money(p.item_revenue)}</td></tr>`));
  document.querySelector('#top-customers').innerHTML=table(['Client','Commandes','Valeur'],customers.map(c=>`<tr><td><strong>${esc(c.customer_name)}</strong><small class="sub">${esc(c.customer_segment)}</small></td><td>${c.paid_orders}</td><td class="money">${money(c.lifetime_gross_revenue)}</td></tr>`));
  const funnel=[['Sessions',conversion.sessions],['Vues produit',conversion.product_views],['Paniers',conversion.carts],['Checkouts',conversion.checkouts],['Achats',conversion.purchases]],funnelMax=Math.max(Number(conversion.sessions),1);
  document.querySelector('#conversion-funnel').innerHTML=`<div class="conversion-score">${conversion.conversion_rate}% <small>conversion globale</small></div>`+funnel.map(x=>`<div class="funnel-row"><span>${x[0]}</span><div class="track"><div class="fill green" style="width:${Number(x[1])/funnelMax*100}%"></div></div><strong>${x[1]}</strong></div>`).join('');
  document.querySelector('#recent-events').innerHTML=events.map(e=>`<div class="event-row"><span class="event-dot"></span><div><strong>${esc(e.event_type.replaceAll('_',' '))}</strong><small>${esc(e.product_name||e.customer_name||'Visiteur anonyme')}</small></div><time>${date(e.event_time)}</time></div>`).join('');
}

async function loadOrders(){const d=await api('/orders?limit=100');document.querySelector('#orders-table').innerHTML=ordersTable(d.items)}
async function loadCustomers(){const d=await api('/customers?limit=100');document.querySelector('#customers-table').innerHTML=table(['Client','Pays','Canal','Segment','Commandes','Valeur client','Inscription'],d.items.map(c=>`<tr><td class="customer-cell"><strong>${esc(c.first_name)} ${esc(c.last_name)}</strong><small>${esc(c.email)}</small></td><td>${esc(c.country_code)}</td><td>${esc(c.acquisition_channel)}</td><td>${badge(c.customer_segment)}</td><td>${c.all_orders}</td><td class="money">${money(c.lifetime_gross_revenue)}</td><td>${date(c.signup_at)}</td></tr>`))}
async function loadProducts(){const d=await api('/products?limit=100');document.querySelector('#products-table').innerHTML=table(['Produit','Catégorie','SKU','Prix','Disponible','Réservé','État'],d.items.map(p=>`<tr><td><strong>${esc(p.product_name)}</strong></td><td>${esc(p.category_name)}</td><td>${esc(p.sku)}</td><td class="money">${money(p.unit_price,p.currency)}</td><td>${p.quantity_available}</td><td>${p.quantity_reserved}</td><td>${badge(p.inventory_status)}</td></tr>`))}

async function loadSupervision(){
  const d=await api('/supervision');
  document.querySelector('#service-health').innerHTML=Object.entries(d.services).map(([name,service])=>`<article class="service-card"><span class="health-dot ${service.status}"></span><div><small>${esc(name)}</small><strong>${esc(service.status)}</strong></div></article>`).join('');
  document.querySelector('#freshness-table').innerHTML=table(['Source','Dernière donnée','Âge','Lignes'],d.freshness.map(x=>`<tr><td><strong>${esc(x.source_name)}</strong></td><td>${date(x.latest_record_at)}</td><td>${esc(x.data_age)}</td><td>${x.row_count}</td></tr>`));
  const executions=d.kestra_executions||[];
  document.querySelector('#kestra-runs').innerHTML=executions.length?table(['Flow','État','Début'],executions.map(x=>`<tr><td>${esc(x.flowId||x.id||'Kestra')}</td><td>${badge(x.state?.current||x.state||'inconnu')}</td><td>${date(x.state?.startDate||x.startDate)}</td></tr>`)):'<div class="empty">Aucune exécution Kestra retournée.</div>';
  const runs=[...(d.pipeline_runs||[]).map(x=>({name:x.pipeline_name,status:x.run_status,start:x.started_at,end:x.finished_at,error:x.error_message,rows:x.rows_written})),...(d.warehouse_runs||[]).map(x=>({name:x.pipeline_name,status:x.status,start:x.started_at,end:x.finished_at,error:null,rows:x.fact_sales}))];
  document.querySelector('#pipeline-runs').innerHTML=runs.length?table(['Pipeline','État','Début','Fin','Lignes','Erreur'],runs.map(x=>`<tr><td><strong>${esc(x.name)}</strong></td><td>${badge(x.status)}</td><td>${date(x.start)}</td><td>${date(x.end)}</td><td>${x.rows??0}</td><td class="error-cell">${esc(x.error||'—')}</td></tr>`)):'<div class="empty">Aucune exécution enregistrée.</div>';
}

const loaders={dashboard:loadDashboard,orders:loadOrders,customers:loadCustomers,products:loadProducts,supervision:loadSupervision};
const titles={dashboard:"Vue d’ensemble",orders:'Commandes',customers:'Clients',products:'Produits & stock',supervision:'Supervision de la plateforme'};
async function show(view){document.querySelectorAll('.view').forEach(x=>x.classList.toggle('active',x.id===view));document.querySelectorAll('.nav-item').forEach(x=>x.classList.toggle('active',x.dataset.view===view));document.querySelector('#page-title').textContent=titles[view];try{await loaders[view]();document.querySelector('#last-updated').textContent=`Mis à jour à ${new Date().toLocaleTimeString('fr-FR',{hour:'2-digit',minute:'2-digit'})}`}catch(e){console.error(e);document.querySelector(`#${view}`).innerHTML='<div class="panel error">Impossible de joindre l’API ShopPulse.</div>'}}
document.querySelectorAll('.nav-item').forEach(b=>b.addEventListener('click',()=>{location.hash=b.dataset.view;show(b.dataset.view)}));
document.querySelectorAll('[data-go]').forEach(b=>b.addEventListener('click',()=>{location.hash=b.dataset.go;show(b.dataset.go)}));
document.querySelector('#refresh').addEventListener('click',async()=>{await show(document.querySelector('.view.active').id);toast('Données actualisées')});
const initialView=location.hash.slice(1);
show(loaders[initialView]?initialView:'dashboard');
