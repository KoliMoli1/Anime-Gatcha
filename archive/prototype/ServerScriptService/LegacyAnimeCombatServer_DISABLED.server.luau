local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local core=RS:WaitForChild('AnimeCombatCore')
local rem=core:WaitForChild('Remotes')
local defs=require(core.Shared:WaitForChild('CharacterDefinitions'))
local rf=rem:WaitForChild('GetCombatLabSnapshot')
local rng=Random.new()
local ids={}
for id in pairs(defs) do table.insert(ids,id) end
table.sort(ids)
local MAX=300
local G={Support=40,Attack=20,Defense=10}
local C={Support=100,Attack=100,Defense=50}
local states={}
local function cls(d)return next(d.Classes)end
local function cost(d,k)return k=='Action2' and(C[cls(d)]or 100)or 0 end
local function actionName(d,k)if k~='Action2'then return k end;local c=cls(d);if c=='Attack'then return'Damage Up'elseif c=='Defense'then return'Taunt'else return'Crit Rate Buff'end end
local function gain(list)local n=0;for i=1,3 do n+=G[cls(defs[list[i]])]or 0 end;return n end
local function fallback()return{ids[1],ids[2]or ids[1],ids[3]or ids[1]}end
local function roster(pl)
 local svc=_G.AnimeGachaProfileService;local prof=svc and svc.GetProfile and svc.GetProfile(pl)
 if not prof or type(prof.SelectedTeam)~='table'then return fallback(),false,'TEAM SELECT REQUIRED: save three characters.'end
 local p,seen={},{}
 for i=1,3 do local id=prof.SelectedTeam[i];if type(id)~='string'or not defs[id]or seen[id]or not prof.OwnedCharacters[id]then return fallback(),false,'Saved team is invalid.'end;seen[id]=true;p[i]=id end
 return p,true,'Saved 3v3 team loaded.'
end
local function new(pl)
 local p,ok,status=roster(pl);local e={ids[3]or ids[1],ids[1],ids[2]or ids[1]}
 local s={p=p,e=e,ok=ok,status=status,ap={nil,nil,nil},ae={'Attack','Attack','Attack'},abp={false,false,false},abe={false,false,false},dbp={false,false,false},dbe={false,false,false},sp=false,se=false,tp={1,2,3},te={1,2,3},hp={},he={},ep=0,ee=0,gp=gain(p),ge=gain(e),turn=1,log={}}
 for i=1,3 do s.hp[i]=defs[p[i]].BaseStats.MaxHealth;s.he[i]=defs[e[i]].BaseStats.MaxHealth end
 s.log[1]=ok and'Energy system ready. Choose actions.'or status
 return s
end
local function get(pl)states[pl]=states[pl]or new(pl);return states[pl]end
local function log(s,t)table.insert(s.log,1,t);while #s.log>16 do table.remove(s.log)end end
local function cyc(v,d,h)for z=1,3 do local n=((v-1+d*z)%3)+1;if(h[n]or 0)>0 then return n end end;return v end
local function snap(s)
 local pt,et={},{}
 for i=1,3 do
  local p,e=defs[s.p[i]],defs[s.e[i]]
  pt[i]={Id=s.p[i],Name=p.DisplayName,Class=cls(p),Stats=table.clone(p.BaseStats),HP=s.hp[i],Action=s.ap[i]or'Choose Action',Target=s.tp[i],Action2Cost=cost(p,'Action2'),Effects={AttackBuff=s.abp[i],DefenseBuff=s.dbp[i],SupportBuff=s.sp}}
  et[i]={Id=s.e[i],Name=e.DisplayName,Class=cls(e),Stats=table.clone(e.BaseStats),HP=s.he[i],Action=s.ae[i],Target=s.te[i],Action2Cost=cost(e,'Action2'),Effects={AttackBuff=s.abe[i],DefenseBuff=s.dbe[i],SupportBuff=s.se}}
 end
 local ch={};for id,d in pairs(defs)do ch[id]={DisplayName=d.DisplayName,Rarity=d.Rarity,Class=cls(d),Stats=table.clone(d.BaseStats)}end
 return{Characters=ch,PlayerTeam=pt,EnemyTeam=et,CanBattle=s.ok,CanResolve=s.ok and s.ap[1]~=nil and s.ap[2]~=nil and s.ap[3]~=nil,TeamStatus=s.status,Energy={Player=s.ep,Enemy=s.ee,Max=MAX,PlayerGain=s.gp,EnemyGain=s.ge},Battle={TurnNumber=s.turn,Log=table.clone(s.log)}}
end
local function dmg(d,t,defended,buffed)
 local raw=d.BaseStats.Attack+(cls(d)=='Attack'and 150 or cls(d)=='Support'and 100 or 70)-(t.Defense*(defended and 1.5 or 1))
 local crit=rng:NextNumber()<(d.BaseStats.CritChance or 0);local mult=crit and(d.BaseStats.CritDamage or 1)or 1
 local n=math.max(1,math.floor(raw*mult+0.5));if buffed then n=math.floor(n*1.5+0.5)end;return n
end
local function activate(s)
 s.sp=false;s.se=false
 for i=1,3 do s.dbp[i]=false;s.dbe[i]=false;if s.ap[i]=='Action2' then local c=cls(defs[s.p[i]]);if c=='Attack'then s.abp[i]=true elseif c=='Defense'then s.dbp[i]=true;for j=1,3 do s.te[j]=i end;log(s,string.format('P%d Taunt forces all enemies to P%d.',i,i)) elseif c=='Support'then s.sp=true end end;if s.ae[i]=='Action2' then local c=cls(defs[s.e[i]]);if c=='Attack'then s.abe[i]=true elseif c=='Defense'then s.dbe[i]=true elseif c=='Support'then s.se=true end end end
end
local function resolve(s)
 if not s.ok then log(s,s.status);return end
 if not(s.ap[1]and s.ap[2]and s.ap[3])then log(s,'Choose actions for all player characters.');return end
 for i=1,3 do
  if s.ap[i]=='Action2' then local c=cost(defs[s.p[i]],'Action2');if s.ep<c then log(s,string.format('P%d lacks energy for Action 2: %d/%d.',i,s.ep,c));s.ap[i]='Attack'end end
  if s.ae[i]=='Action2' then local c=cost(defs[s.e[i]],'Action2');if s.ee<c then s.ae[i]='Attack'end end
 end
 for i=1,3 do if s.ap[i]=='Action2'then s.ep-=cost(defs[s.p[i]],'Action2')end;if s.ae[i]=='Action2'then s.ee-=cost(defs[s.e[i]],'Action2')end end
 activate(s)
 for i=1,3 do
  local p,e=defs[s.p[i]],defs[s.e[i]];local pd,ed=0,0
  if s.ap[i]=='Attack'and s.he[s.tp[i]]>0 then pd=dmg(p,defs[s.e[s.tp[i]]].BaseStats,s.dbe[s.tp[i]],s.abp[i]);s.he[s.tp[i]]=math.max(0,s.he[s.tp[i]]-pd)end
  if s.ae[i]=='Attack'and s.hp[s.te[i]]>0 then ed=dmg(e,defs[s.p[s.te[i]]].BaseStats,s.dbp[s.te[i]],s.abe[i]);s.hp[s.te[i]]=math.max(0,s.hp[s.te[i]]-ed)end
  log(s,string.format('P%d %s %s -> E%d -%d | E%d %s %s -> P%d -%d',i,p.DisplayName,s.ap[i],s.tp[i],pd,i,e.DisplayName,s.ae[i],s.te[i],ed))
 end
 s.ep=math.clamp(s.ep+s.gp,0,MAX);s.ee=math.clamp(s.ee+s.ge,0,MAX);log(s,string.format('Energy generated: P +%d = %d/%d | E +%d = %d/%d',s.gp,s.ep,MAX,s.ge,s.ee,MAX));s.turn+=1;s.ap={nil,nil,nil};s.ae={'Attack','Attack','Attack'}
end
rf.OnServerInvoke=function(pl,r)
 local s=get(pl);r=r or{}
 if r.Action=='ResetBattle'then states[pl]=new(pl);s=states[pl]
 elseif r.Action=='SelectTarget'then local t=r.Side=='Player'and s.tp or s.te;local h=r.Side=='Player'and s.he or s.hp;t[r.Slot]=cyc(t[r.Slot],r.Direction or 1,h)
 elseif r.Action=='SetAction'and(r.Kind=='Attack'or r.Kind=='Action2')then local list=r.Side=='Player'and s.p or s.e;local energy=r.Side=='Player'and s.ep or s.ee;local d=defs[list[r.Slot]];if r.Kind=='Action2'and energy<cost(d,'Action2')then log(s,string.format('%s%d needs %d energy (has %d).',r.Side:sub(1,1),r.Slot,cost(d,'Action2'),energy))elseif r.Side=='Player'then s.ap[r.Slot]=r.Kind else s.ae[r.Slot]=r.Kind end
 elseif r.Action=='ResolveTurn'then resolve(s)end
 return snap(s)
end
Players.PlayerRemoving:Connect(function(pl)states[pl]=nil end)
print('[AnimeCombatServer] Energy and class Action 2 effects online.')
