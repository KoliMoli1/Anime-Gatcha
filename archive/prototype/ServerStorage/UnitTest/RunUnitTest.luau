local expect = {}
local function fmt(v) return type(v)=='string' and string.format('%q',v) or tostring(v) end
function expect.equal(actual, expected) if actual~=expected then error(string.format('expected %s, got %s',fmt(expected),fmt(actual)),2) end end
function expect.truthy(value) if not value then error('expected truthy, got '..fmt(value),2) end end
function expect.falsy(value) if value then error('expected falsy, got '..fmt(value),2) end end
function expect.near(actual, expected, tolerance) tolerance=tolerance or 1e-6; if type(actual)~='number' or math.abs(actual-expected)>tolerance then error(string.format('expected %s near %s',fmt(actual),fmt(expected)),2) end end
function expect.throws(fn) local ok,err=pcall(fn); if ok then error('expected function to throw',2) end; return err end

local function runOne(fn, timeout)
 local done,ok,err=false,false,nil; local start=os.clock()
 task.spawn(function() ok,err=pcall(fn); done=true end)
 while not done and os.clock()-start<timeout do task.wait() end
 if not done then return 'timeout',os.clock()-start,'exceeded timeout' end
 return ok and 'pass' or 'fail',os.clock()-start,ok and nil or tostring(err)
end

return function(filter, timeout)
 timeout=timeout or 5
 local cases=game:GetService('ServerStorage').UnitTest.Cases
 local totals={run=0,passed=0,failed=0}
 for _,module in ipairs(cases:GetDescendants()) do
  if module:IsA('ModuleScript') and (not filter or string.find(module.Name,filter,1,true)) then
   local okRequire,caseFn=pcall(require,module)
   if not okRequire or type(caseFn)~='function' then totals.run+=1;totals.failed+=1;warn('[FAIL] '..module.Name..' did not return test function: '..tostring(caseFn))
   else
    local t={expect=expect}
    function t.test(name,fn)
     totals.run+=1; local status,elapsed,message=runOne(fn,timeout)
     if status=='pass' then totals.passed+=1;print(string.format('[PASS] %s > %s (%.3fs)',module.Name,name,elapsed))
     else totals.failed+=1;warn(string.format('[%s] %s > %s | %s',string.upper(status),module.Name,name,message)) end
    end
    local okRun,runErr=pcall(caseFn,t)
    if not okRun then totals.run+=1;totals.failed+=1;warn('[FAIL] '..module.Name..' case registration: '..tostring(runErr)) end
   end
  end
 end
 print(string.format('[SUMMARY] %d run, %d passed, %d failed',totals.run,totals.passed,totals.failed))
 return totals
end
