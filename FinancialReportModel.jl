### A Pluto.jl notebook ###
# v0.14.8

using Markdown
using InteractiveUtils

# ╔═╡ dd7b857f-4e75-4bc8-b904-f94f9b220959
using Test

# ╔═╡ d5cea183-ac32-4c5a-b1df-0cebe4421536
using PlutoUI

# ╔═╡ 4104c8bc-4e8b-4988-88c3-05699b9829fb
md"FinancialReportModel"

# ╔═╡ 4b6fef6e-f6ab-4d17-b801-82785324bc75
md"# What is this for? "

# ╔═╡ d6827019-3284-471c-983f-124b1dcf4bb5
md"""
## Financial modelling
There is a broad segment of financial modelling that tries to calculate future state of a company under different circumstances. It is known as a *financial model* or *a 3-way financial model* or *a 3 statement financial model*. It can be used for business valuation, asessment of business robustness, etc. [More] (https://corporatefinanceinstitute.com/resources/knowledge/modeling/types-of-financial-models/)

Conceptually the model is quite straitforward: given a number of assumptions and a starting balance sheet, one applies accounting rules (reporting, more precisely) and calculates future state of accounts.

The model has descrete time (years, quarters), it is deterministic, dependences are known beforehand. So the only goal is to simulate.
"""

# ╔═╡ 1ce2d04c-6c93-42b0-9fe2-4ddccd891674
md"""

## Pluto vs Excel
Usually this type of calculations is done in Excel, due to its ubuquity, and responsiveness. It is quite easy to make what-if analysis. Pluto, on the other hand, can be a substitution for this interface.

However, Excel is akin to a list of paper, one can draw there anything. It is very error prone. The modeller has to be very disciplined in order to keep trust to the calculation results. 

There are modelling standards that try to reduce the modelling risk by imposing restrictions on the modeller. One have to adhere to the special worksheet structure, include checks for model integrity, include checks for business logic (e.g. negative cash), etc.

One rule reads as \"one row -- one formula\". In this case the number of unique formulas reduces substantially (degrees of magnitude) and the modeller (or an auditor) can easier keep track of what is behind those walls of figures.

Basicly these formulas represent relationships betweeen accounts and one can model only those. It is quite similar to ODEs. This module tries to do exacly this.

It is interesting that so far the module is Pluto agnostic.

"""

# ╔═╡ 29468f52-5366-4c16-a667-fc3df7b25b3c
md"""
## Why not the ...
### ... DataFrames
I suspect that it will be tricky to implement reactivity for objects inside a df. Another point is the less dependencies, the better.


### ... Modeling Toolkit & DifferentialEquations
I don't know, too ignorant for this. 
On one hand, the model looks like a DE with discrete time.
On another hand, DE might be an overkill.
"""

# ╔═╡ 3a47d90f-7e51-42d3-81b4-3ff7d86bf154
md"
# TODO
* build own DAG
* calculate based on DAG <- can be solved by reactivity
* check if DAG is acyclic
* adding variable together with its initial value?
* function for restrictions?
* If Accounts have the same units, they can be added.
* reactivity. Via Observables (?)
* make errors readable. It is now hard to understand what and where goes wrong
* error if DAG refers to a missing
* error if parameters used in formula with wrong syntax: scalar in place for vecrot and vice versa
* Base.show() for model, account
* prettytables? intercept if for Pluto (mime::MIME\"text/html\")"


# ╔═╡ b2802ff6-de7b-4b3b-883c-79d53896da0b
md"# Module"

# ╔═╡ 5adf2e27-7437-42a9-84cb-1375f06862ae
begin
	mutable struct Account
		acc::Array{Union{Number, Missing}, 1}
		unit::Symbol
	end

	Account(len::Number, unit::Symbol) = Account(fill(missing, len), unit)
end

# ╔═╡ 1a04ad02-41ad-4675-a887-ec8e27928987
begin
	struct Finmodel
		n_periods::Integer
		variables::Dict{Symbol, Account}
		parameters
		rules
	end
	
	Finmodel(n_periods::Integer) = Finmodel(n_periods, Dict(), Dict(), [])
end

# ╔═╡ e24bafaf-b7f8-470b-8dbb-c21f25642800
Base.length(acc::Account) = length(acc.acc)

# ╔═╡ 0607acd3-e09c-4440-90de-931653d92769
function add_variables!(model::Finmodel, variables)
	for v in variables
		# :unit symbol is a temp stab
		model.variables[v] = Account(model.n_periods+1, :unit)
	end
end

# ╔═╡ 12c0a5c6-1eb7-4ec9-a707-cff8c058f2e8
function set_initials!(model::Finmodel, init)
	for (var, val) in init
		model[var][1] = val
	end
end

# ╔═╡ 8cebec2d-586e-4835-bf2c-dc0715cbdfc4
# The name of model variable is unknown at runtime.
# It depends upon the user. This macro passes model name as a string.

macro rules(model, args)
	modelname = string(model)
	return :(set_rules!($(esc(model)), $modelname, $(esc(args))))
end

# ╔═╡ 5097e2d3-7cb2-4de3-a7de-a63bd5d2c69d
# overwrites existing parameters
function set_parameters!(model::Finmodel, params)
	while length(model.parameters)>0
		pop!(model.parameters)
	end

	for (param, val) in params
		@assert length(val)==1 || length(val)==model.n_periods+1
		model.parameters[param] = val
	end
end

# ╔═╡ e8e659ee-5cf6-42ef-b8b2-13a863ffe02b
function parse_formula_on_register(modelname, formula)
	# :var[smth] reference
	replacement = SubstitutionString(modelname * s"[\1][_$time_\2]")
	formula = replace(formula, r"(:\w+)\[([\+-]?\d+)]" => replacement)
	# :parameter reference
	replacement = SubstitutionString(modelname * s"[\1]")
	replace(formula, r"(?<!\[)(:\w+)(?!\])" => replacement)
end

# ╔═╡ c3045fa3-4035-43b1-bff9-1c96dab85326
# overwrites existing rules
function set_rules!(model::Finmodel, modelname, rules)
	while length(model.rules)>0
		pop!(model.rules)
	end

	for (var, rule) in rules
			push!(model.rules,(var, parse_formula_on_register(modelname, rule)))
	end
end

# ╔═╡ febaa730-6616-400a-b451-00d01732542f
function parse_formula_on_calc(formula, t)
	replace(formula, r"\_\$time\_" => "$t")
end

# ╔═╡ 0038633e-3fda-4743-98cd-bb861ca9ebb3
# common [] interface for both vars and parameters
function Base.getindex(m::Finmodel, name)
	if haskey(m.variables, name)
		return m.variables[name]
	elseif haskey(m.parameters, name)
		return m.parameters[name]
	else
		throw(KeyError(name))
	end
end

# ╔═╡ fe7f64de-a0b9-42fd-8cd4-bc4d6f5eedc6
function Base.getindex(m::Finmodel, name, idx::Number)
	if haskey(m.variables, name)
		return m.variables[name][idx]
	elseif haskey(m.parameters, name)
		return m.parameters[name][idx]
	else
		throw(KeyError(name))
	end
end

# ╔═╡ 4a94087d-1953-4409-ac97-44738bc21afc
function Base.getindex(acc::Account, idx)
	return acc.acc[idx]
end

# ╔═╡ acb16d3c-c3f6-4241-994f-1b48967fc816
function Base.setindex!(acc::Account, rhs, idx)
	return acc.acc[idx] =  rhs
end

# ╔═╡ 594c2cbe-0929-43dc-b736-36b6d21d22f6
# cycles over timesteps and calculates var value
# TODO there is a problem if the rules are recorded out of order.
# E.g. for rules "b = a * 2, aₜ=aₜ-1 + 5". calculate! will try to compute b first
# and will result in an error.

function calculate!(m::Finmodel)
	for t in 2:m.n_periods+1
		for (var, rule) in m.rules
			formula = parse_formula_on_calc(rule, t)
			# TODO: somehow catch refs to missing in order to produce
			# meaningful error text
			try
				m.variables[var][t] = eval(Meta.parse(formula))
			finally
				# @show formula
			end
		end
	end
end

# ╔═╡ a31bed2b-f6f4-4777-83c7-cd1d9572a14f


# ╔═╡ ff014c1f-fbff-4db3-aa86-62668af8b71d
md"# Tests"

# ╔═╡ 87ec27f9-a05b-4cfa-95db-7be344f0f868
@testset "Integration test" begin

	# TODO get rid of global. eval() works only for global context
	n = 40
    global model1 = Finmodel(n)
	@test model1.n_periods==n

	@testset "Add variables" begin
		add_variables!(model1,[:a, :b])
		@test isnothing(model1[:a]) == false
		@test isnothing(model1[:b]) == false
		@test length(model1[:a]) == n + 1
	end
	
	a_init = 10
	b_init = 30
	@testset "Set initials" begin
		set_initials!(model1, [:a => a_init, :b => b_init])
		@test model1[:a][1] == a_init
		@test model1[:b][1] == b_init
		@test ismissing(model1[:a][2])
	end
	
	@testset "Set parameter" begin
		set_parameters!(model1, [:c => 5])
		@test model1[:c] == 5
	end
	
	@testset "Formula parsing" begin
		@test eval(Meta.parse("model1[:a][1]*4")) == a_init * 4
		test_formula1 = parse_formula_on_register("model1", ":a[-1]+:b[-1]")
		parsed_f = parse_formula_on_calc(test_formula1, 2)
		@test eval(Meta.parse(parsed_f)) == a_init * 4
	end
	
	@testset "Setting rules" begin
		set_rules!(model1, "model1", [:a => ":a[-1]+1", :b => ":a[+0]*3"])
		@test !isnothing(model1.rules[1])
		@test length(model1.rules) == 2
	end
	
	@testset "Calculations" begin
		calculate!(model1)
		@test model1[:a][41] == a_init + n * 1
		@test model1[:b][41] == (a_init + n * 1) * 3
	end
end

# ╔═╡ 9b837bf5-572f-4f8d-84c7-e958f951fc75
model1

# ╔═╡ 62a698bb-dbec-42b9-aa29-e940f79d7611
@testset "Parameters" begin

	# TODO get rid of global. eval() works only for global context
	n2 = 40
    global model2 = Finmodel(n2)
	add_variables!(model2,[:a, :b])
	
	@testset "Vector parameter" begin
		set_parameters!(model2, [:d => 8, :e => repeat([6], 41)])
		@test length(model2[:e]) == n2 + 1
	end
	
	# test for using parameter
	# scalar prm instead of vector
	# vector prm instead of scalar
	# should a scalar prm broadcasted to a vector prm?
	# vector prm of length that deviates from the number of periods
end

# ╔═╡ 35442681-d3b4-48c4-b0da-d83f6dfdca93
md"# Elaborated example (WIP)"

# ╔═╡ 49344309-23b0-4edb-b572-3271d1f5bccd
fm = Finmodel(12)

# ╔═╡ 39c1c3f0-4329-440f-be63-4a753bfea510
set_parameters!(fm, [
		:production => fill(10, 13),
		:price => 8,
		:cost => 4,
		:depreciation => 2,
		:incometaxrate => 0.2
		])

# ╔═╡ 9ab3aeb4-3db1-4655-a984-fd5c21fdae48
add_variables!(fm, [
		:revenue, :cogs, :ebitda, :operatingp, :incometax, :netp,
		:cash, :fixedassets, :retained])

# ╔═╡ 3b0a6701-7102-4798-b364-b3989d6f2762
set_initials!(fm, [
		:cash => 0, 
		:fixedassets => 100, 
		:retained => 100])

# ╔═╡ 8c389a79-5330-4d5a-a21e-acb587b9ab65
@rules fm [
		:revenue => ":production[+0] * :price",
		:cogs => ":production[+0] * :cost",
		:operatingp => ":revenue[+0] - :cogs[+0] - :depreciation",
		:incometax => ":operatingp[+0] * :incometaxrate",
		:netp => ":operatingp[+0] - :incometax[+0]",
	
		:cash => ":cash[-1] + :netp[+0]",
		:retained => ":retained[-1] + :netp[+0]",
		:fixedassets => ":fixedassets[-1]"	
		]

# ╔═╡ cd7ddb24-de63-4c9f-85c9-aa6f7720f452
fm

# ╔═╡ bfb866fd-58a1-44d5-b5eb-8856a7a30566
calculate!(fm)

# ╔═╡ 8bb1e62a-541b-48d7-9b2e-de196f6fd080
fm

# ╔═╡ 64ed55b4-adc0-47c9-8b73-490d8af9cb1f
fm[:production]

# ╔═╡ e2d4aaef-c74a-4733-a0cb-8161b8f1159c
fm[:retained].acc .≈ fm[:fixedassets].acc + fm[:cash].acc

# ╔═╡ 705e87b8-5c65-43c1-9de5-413c6b967c61
PlutoUI.TableOfContents(aside = true)

# ╔═╡ Cell order:
# ╟─4104c8bc-4e8b-4988-88c3-05699b9829fb
# ╟─4b6fef6e-f6ab-4d17-b801-82785324bc75
# ╟─d6827019-3284-471c-983f-124b1dcf4bb5
# ╟─1ce2d04c-6c93-42b0-9fe2-4ddccd891674
# ╟─29468f52-5366-4c16-a667-fc3df7b25b3c
# ╟─3a47d90f-7e51-42d3-81b4-3ff7d86bf154
# ╟─b2802ff6-de7b-4b3b-883c-79d53896da0b
# ╠═1a04ad02-41ad-4675-a887-ec8e27928987
# ╠═5adf2e27-7437-42a9-84cb-1375f06862ae
# ╠═e24bafaf-b7f8-470b-8dbb-c21f25642800
# ╠═0607acd3-e09c-4440-90de-931653d92769
# ╠═12c0a5c6-1eb7-4ec9-a707-cff8c058f2e8
# ╠═8cebec2d-586e-4835-bf2c-dc0715cbdfc4
# ╠═c3045fa3-4035-43b1-bff9-1c96dab85326
# ╠═5097e2d3-7cb2-4de3-a7de-a63bd5d2c69d
# ╠═e8e659ee-5cf6-42ef-b8b2-13a863ffe02b
# ╠═febaa730-6616-400a-b451-00d01732542f
# ╠═0038633e-3fda-4743-98cd-bb861ca9ebb3
# ╠═fe7f64de-a0b9-42fd-8cd4-bc4d6f5eedc6
# ╠═4a94087d-1953-4409-ac97-44738bc21afc
# ╠═acb16d3c-c3f6-4241-994f-1b48967fc816
# ╠═594c2cbe-0929-43dc-b736-36b6d21d22f6
# ╠═a31bed2b-f6f4-4777-83c7-cd1d9572a14f
# ╟─ff014c1f-fbff-4db3-aa86-62668af8b71d
# ╠═dd7b857f-4e75-4bc8-b904-f94f9b220959
# ╠═87ec27f9-a05b-4cfa-95db-7be344f0f868
# ╠═9b837bf5-572f-4f8d-84c7-e958f951fc75
# ╠═62a698bb-dbec-42b9-aa29-e940f79d7611
# ╟─35442681-d3b4-48c4-b0da-d83f6dfdca93
# ╠═49344309-23b0-4edb-b572-3271d1f5bccd
# ╠═39c1c3f0-4329-440f-be63-4a753bfea510
# ╠═9ab3aeb4-3db1-4655-a984-fd5c21fdae48
# ╠═3b0a6701-7102-4798-b364-b3989d6f2762
# ╠═8c389a79-5330-4d5a-a21e-acb587b9ab65
# ╠═cd7ddb24-de63-4c9f-85c9-aa6f7720f452
# ╠═bfb866fd-58a1-44d5-b5eb-8856a7a30566
# ╠═8bb1e62a-541b-48d7-9b2e-de196f6fd080
# ╠═64ed55b4-adc0-47c9-8b73-490d8af9cb1f
# ╠═e2d4aaef-c74a-4733-a0cb-8161b8f1159c
# ╟─d5cea183-ac32-4c5a-b1df-0cebe4421536
# ╟─705e87b8-5c65-43c1-9de5-413c6b967c61
