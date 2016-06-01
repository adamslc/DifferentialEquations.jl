"""
FEMSolution

Holds the data for the solution to a finite element problem.

### Fields

* `femMesh::FEMmesh`: The finite element mesh the problem was solved on.
* `u::Array{Float64}`: The solution (at the final timepoint)
* `trueKnown::Bool`: Boolean flag for if the true solution is given.
* `uTrue::AbstractArrayOrVoid`: The true solution at the final timepoint.
* `l2Err::NumberOrVoid`: The L2 error between u and uTrue.
* `h1Err::NumberOrVoid`: The H1 error between u and uTrue.
* `maxErr::NumberOrVoid`: The nodal maximum error between u and uTrue.
* `nodeErr2::NumberOrVoid`: The nodal l2 error between y abd uTrue.
* `appxTrue::Bool`: Boolean flag for if uTrue was an approximation.
* `uFull`::AbstractArrayOrVoid`: u over time. Only saved if `fullSave=true`
is specified in the solver.
* `tFull::AbstractArrayOrVoid`: All the t's in the solution. Only saved if `fullSave=true`
is specified in the solver.
* `fullSave::Bool`: True if solver saved the extra timepoints.

"""
type FEMSolution <: DESolution
  femMesh::FEMmesh
  u::Array{Float64}
  trueKnown::Bool
  uTrue::AbstractArrayOrVoid
  errors#::Dict{String,Float64}
  appxTrue::Bool
  timeSeries#::GrowableArray
  tFull::AbstractArrayOrVoid
  prob::DEProblem
  fullSave::Bool
  function FEMSolution(femMesh::FEMmesh,u,uTrue,sol,Du,timeSeries,tFull,prob;fullSave=true)
    errors = Dict("L2"=>getL2error(femMesh,sol,u),"H1"=>getH1error(femMesh,Du,u),
                  "l∞"=> maximum(abs(u-uTrue)), "l2"=> norm(u-uTrue,2))
    return(new(femMesh,u,true,uTrue,errors,false,timeSeries,tFull,prob,true))
  end
  FEMSolution(femMesh,u,uTrue,sol,Du,prob) = FEMSolution(femMesh::FEMmesh,u,uTrue,sol,Du,nothing,nothing,prob,fullSave=false)
  function FEMSolution(femMesh::FEMmesh,u::AbstractArray,prob)
    return(FEMSolution(femMesh,u,nothing,nothing,prob,fullSave=false))
  end
  function FEMSolution(femMesh::FEMmesh,u::AbstractArray,timeSeries,tFull,prob;fullSave=true)
    return(new(femMesh,u,false,nothing,Dict{String,Float64},false,timeSeries,tFull,prob,fullSave))
  end
end

type SDESolution <: DESolution
  u#::AbstractArrayOrNumber
  trueKnown::Bool
  uTrue#::AbstractArrayOrNumber
  errors#::Dict{}
  uFull::AbstractArrayOrVoid
  tFull::AbstractArrayOrVoid
  WFull::AbstractArrayOrVoid
  solFull::AbstractArrayOrVoid
  appxTrue::Bool
  fullSave::Bool
  function SDESolution(u;uFull=nothing,solFull=nothing,tFull=nothing,WFull=nothing)
    fullSave = uFull == nothing
    trueKnown = false
    return(new(u,trueKnown,nothing,Dict(),uFull,tFull,WFull,solFull,false,fullSave))
  end
  function SDESolution(u,uTrue;uFull=nothing,solFull=nothing,tFull=nothing,WFull=nothing)
    fullSave = uFull != nothing
    trueKnown = true
    errors = Dict("final"=>abs(u-uTrue))
    if fullSave
      errors = Dict("final"=>mean(abs(u-uTrue)),"l∞"=>maximum(abs(uFull-solFull)),"l2"=>sqrt(mean((uFull-solFull).^2)))
    end
    return(new(u,trueKnown,uTrue,errors,uFull,tFull,WFull,solFull,false,fullSave))
  end
  #Required to convert pmap results
  SDESolution(a::Any) = new(a.u,a.trueKnown,a.uTrue,a.errors,a.uFull,a.tFull,a.WFull,a.solFull,a.appxTrue,a.fullSave)
end

type ODESolution <: DESolution
  u#::AbstractArrayOrNumber
  trueKnown::Bool
  uTrue#::AbstractArrayOrNumber
  errors#::Dict{}
  uFull::AbstractArrayOrVoid
  tFull::AbstractArrayOrVoid
  solFull::AbstractArrayOrVoid
  appxTrue::Bool
  fullSave::Bool
  function ODESolution(u;uFull=nothing,solFull=nothing,tFull=nothing)
    fullSave = uFull == nothing
    trueKnown = false
    return(new(u,trueKnown,nothing,Dict(),uFull,tFull,solFull,false,fullSave))
  end
  function ODESolution(u,uTrue;uFull=nothing,solFull=nothing,tFull=nothing)
    fullSave = uFull != nothing
    trueKnown = true
    errors = Dict("final"=>abs(u-uTrue))
    if fullSave
      errors = Dict("final"=>mean(abs(u-uTrue)),"l∞"=>maximum(abs(uFull-solFull)),"l2"=>sqrt(mean((uFull-solFull).^2)))
    end
    return(new(u,trueKnown,uTrue,errors,uFull,tFull,solFull,false,fullSave))
  end
end

type StokesSolution <: DESolution
  u
  v
  p
  uTrue
  vTrue
  pTrue
  mesh::FDMMesh
  trueKnown::Bool
  errors
  converrors
  StokesSolution(u,v,p,uTrue,vTrue,pTrue,mesh,trueKnown;errors=nothing,converrors=nothing) = new(u,v,p,uTrue,vTrue,pTrue,mesh,trueKnown,errors,converrors)
end

"""
appxTrue!(res,res2)

Adds the solution from res2 to the FEMSolution object res.
Useful to add a quasi-true solution when none is known by
computing once at a very small time/space step and taking
that solution as the "true" solution
"""
function appxTrue!(res::FEMSolution,res2::FEMSolution)
  res.uTrue = res2.u
  res.errors = Dict("l∞"=>maximum(abs(res.u-res.uTrue)),"l2"=>norm(res.u-res.uTrue,2))
  res.appxTrue = true
end

"""
S = FEMSolutionTS(uFull::GrowableArray,numVars::Int)
S[i][j] => Variable i at time j.
"""
function FEMSolutionTS(uFull::GrowableArray,numVars::Int)
  G = GrowableArray(uFull[1][:,1])
  for j = 2:length(uFull)
    push!(G,uFull[j][:,1])
  end
  ts = GrowableArray(G)
  if numVars > 1
    for i=2:numVars
      G = GrowableArray(uFull[1][:,i])
      for j = 2:length(uFull)
        push!(G,uFull[j][:,i])
      end
      push!(ts,G)
    end
  end
  return(ts)
end
