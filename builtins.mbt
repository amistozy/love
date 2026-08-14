///|
/// 尝试执行内置谓词。返回 Some(成功与否) 表示已处理，None 表示非内置。
fn Engine::try_builtin(
  engine : Engine,
  name : String,
  args : Array[LoveTerm],
  f : Frame,
) -> Bool? {
  let n = args.length()
  match name {
    "true" if n == 0 => Some(true)
    "fail" if n == 0 => Some(false)
    "!" if n == 0 => {
      engine.cps.truncate(f.barrier)
      Some(true)
    }
    "," if n == 2 => {
      engine.goals.push({ term: args[1], ci: 0, barrier: f.barrier })
      engine.goals.push({ term: args[0], ci: 0, barrier: f.barrier })
      Some(true)
    }
    ";" if n == 2 => {
      let b = engine.cps.length()
      engine.cps.push({
        trail_len: engine.subst.trail.length(),
        goals_snapshot: snapshot_goals(engine.goals),
        kind: CPKind::PushTerm(args[1], b),
      })
      engine.goals.push({ term: args[0], ci: 0, barrier: b })
      Some(true)
    }
    "->" if n == 2 => {
      let b = engine.cps.length()
      engine.goals.push({ term: args[1], ci: 0, barrier: b })
      engine.goals.push({ term: LoveTerm::Atom("!"), ci: 0, barrier: b })
      engine.goals.push({ term: args[0], ci: 0, barrier: b })
      Some(true)
    }
    "->" if n == 3 => {
      let b = engine.cps.length()
      engine.cps.push({
        trail_len: engine.subst.trail.length(),
        goals_snapshot: snapshot_goals(engine.goals),
        kind: CPKind::PushTerm(args[2], b),
      })
      engine.goals.push({ term: args[1], ci: 0, barrier: b })
      engine.goals.push({ term: LoveTerm::Atom("!"), ci: 0, barrier: b })
      engine.goals.push({ term: args[0], ci: 0, barrier: b })
      Some(true)
    }
    "\\+" if n == 1 => {
      let b = engine.cps.length()
      engine.cps.push({
        trail_len: engine.subst.trail.length(),
        goals_snapshot: snapshot_goals(engine.goals),
        kind: CPKind::PushTerm(LoveTerm::Atom("true"), b),
      })
      engine.goals.push({ term: LoveTerm::Atom("fail"), ci: 0, barrier: b })
      engine.goals.push({ term: LoveTerm::Atom("!"), ci: 0, barrier: b })
      engine.goals.push({ term: args[0], ci: 0, barrier: b })
      Some(true)
    }
    "call" if n == 1 => {
      engine.goals.push({ term: args[0], ci: 0, barrier: f.barrier })
      Some(true)
    }
    "once" if n == 1 => {
      let b = engine.cps.length()
      engine.goals.push({ term: LoveTerm::Atom("true"), ci: 0, barrier: b })
      engine.goals.push({ term: LoveTerm::Atom("!"), ci: 0, barrier: b })
      engine.goals.push({ term: args[0], ci: 0, barrier: b })
      Some(true)
    }
    "repeat" if n == 0 => {
      engine.cps.push({
        trail_len: engine.subst.trail.length(),
        goals_snapshot: snapshot_goals(engine.goals),
        kind: CPKind::PushTerm(LoveTerm::Atom("repeat"), f.barrier),
      })
      Some(true)
    }
    // ---------- 合一与项检查 ----------
    "=" if n == 2 => Some(unify(engine.subst, args[0], args[1]))
    "\\=" if n == 2 => {
      let len = engine.subst.trail.length()
      let ok = unify(engine.subst, args[0], args[1])
      engine.subst.unbind_to(len)
      Some(!ok)
    }
    "==" if n == 2 => Some(term_equal(engine.subst, args[0], args[1]))
    "\\==" if n == 2 => Some(!term_equal(engine.subst, args[0], args[1]))
    "unify_with_occurs_check" if n == 2 =>
      Some(unify(engine.subst, args[0], args[1]))
    "var" if n == 1 =>
      Some(
        match engine.subst.deref(args[0]) {
          LoveTerm::Var(_) => true
          _ => false
        },
      )
    "nonvar" if n == 1 =>
      Some(
        match engine.subst.deref(args[0]) {
          LoveTerm::Var(_) => false
          _ => true
        },
      )
    "atom" if n == 1 =>
      Some(
        match engine.subst.deref(args[0]) {
          LoveTerm::Atom(_) => true
          _ => false
        },
      )
    "number" if n == 1 =>
      Some(
        match engine.subst.deref(args[0]) {
          LoveTerm::Int(_) | LoveTerm::Float(_) => true
          _ => false
        },
      )
    "integer" if n == 1 =>
      Some(
        match engine.subst.deref(args[0]) {
          LoveTerm::Int(_) => true
          _ => false
        },
      )
    "float" if n == 1 =>
      Some(
        match engine.subst.deref(args[0]) {
          LoveTerm::Float(_) => true
          _ => false
        },
      )
    "string" if n == 1 =>
      Some(
        match engine.subst.deref(args[0]) {
          LoveTerm::Str(_) => true
          _ => false
        },
      )
    "atomic" if n == 1 =>
      Some(
        match engine.subst.deref(args[0]) {
          LoveTerm::Atom(_)
          | LoveTerm::Int(_)
          | LoveTerm::Float(_)
          | LoveTerm::Str(_)
          | LoveTerm::ListNil => true
          _ => false
        },
      )
    "compound" if n == 1 =>
      Some(
        match engine.subst.deref(args[0]) {
          LoveTerm::Struct(_, _) | LoveTerm::ListCons(_, _) => true
          _ => false
        },
      )
    "callable" if n == 1 =>
      Some(
        match engine.subst.deref(args[0]) {
          LoveTerm::Atom(_) | LoveTerm::Struct(_, _) => true
          _ => false
        },
      )
    "ground" if n == 1 => Some(!contains_any_var(engine.subst.deref(args[0])))
    "functor" if n == 3 => Some(builtin_functor(engine, args))
    "arg" if n == 3 => Some(builtin_arg(engine, args))
    "=.." if n == 2 => Some(builtin_univ(engine, args))
    "atom_length" if n == 2 => Some(builtin_atom_length(engine, args))
    "atom_concat" if n == 3 => Some(builtin_atom_concat(engine, args))
    "sub_atom" if n == 5 => Some(builtin_sub_atom(engine, args))
    "compare" if n == 3 => {
      // compare(Order, X, Y)
      let o = term_order(engine.subst, args[1], args[2])
      let ord = if o < 0 { "<" } else if o > 0 { ">" } else { "=" }
      Some(unify(engine.subst, args[0], LoveTerm::Atom(ord)))
    }
    "@<" if n == 2 => Some(term_order(engine.subst, args[0], args[1]) < 0)
    "@=<" if n == 2 => Some(term_order(engine.subst, args[0], args[1]) <= 0)
    "@>" if n == 2 => Some(term_order(engine.subst, args[0], args[1]) > 0)
    "@>=" if n == 2 => Some(term_order(engine.subst, args[0], args[1]) >= 0)
    // ---------- 算术 ----------
    "is" if n == 2 =>
      match eval_arith(engine.subst, args[1]) {
        None => Some(false)
        Some(Arith::AInt(v)) =>
          Some(unify(engine.subst, args[0], LoveTerm::Int(v)))
        Some(Arith::AFloat(v)) =>
          Some(unify(engine.subst, args[0], LoveTerm::Float(v)))
      }
    "=:=" if n == 2 =>
      match
        (eval_arith(engine.subst, args[0]), eval_arith(engine.subst, args[1])) {
        (Some(a), Some(b)) => Some(arith_compare(a, b) == 0)
        _ => Some(false)
      }
    "=\\=" if n == 2 =>
      match
        (eval_arith(engine.subst, args[0]), eval_arith(engine.subst, args[1])) {
        (Some(a), Some(b)) => Some(arith_compare(a, b) != 0)
        _ => Some(false)
      }
    "<" if n == 2 =>
      match
        (eval_arith(engine.subst, args[0]), eval_arith(engine.subst, args[1])) {
        (Some(a), Some(b)) => Some(arith_compare(a, b) < 0)
        _ => Some(false)
      }
    "=<" if n == 2 =>
      match
        (eval_arith(engine.subst, args[0]), eval_arith(engine.subst, args[1])) {
        (Some(a), Some(b)) => Some(arith_compare(a, b) <= 0)
        _ => Some(false)
      }
    ">" if n == 2 =>
      match
        (eval_arith(engine.subst, args[0]), eval_arith(engine.subst, args[1])) {
        (Some(a), Some(b)) => Some(arith_compare(a, b) > 0)
        _ => Some(false)
      }
    ">=" if n == 2 =>
      match
        (eval_arith(engine.subst, args[0]), eval_arith(engine.subst, args[1])) {
        (Some(a), Some(b)) => Some(arith_compare(a, b) >= 0)
        _ => Some(false)
      }
    "between" if n == 3 => Some(builtin_between(engine, args))
    "plus" if n == 3 => Some(builtin_plus(engine, args))
    // ---------- 列表 ----------
    "sort" if n == 2 => Some(builtin_sort(engine, args, true))
    "msort" if n == 2 => Some(builtin_sort(engine, args, false))
    "maplist" if n == 2 => Some(builtin_maplist(engine, args, f))
    // ---------- 动态数据库 ----------
    "assertz" if n == 1 => {
      let c = clause_from_term(engine.subst.deref(args[0]))
      engine.program.assert_clause(c, false)
      Some(true)
    }
    "asserta" if n == 1 => {
      let c = clause_from_term(engine.subst.deref(args[0]))
      engine.program.assert_clause(c, true)
      Some(true)
    }
    "retract" if n == 1 => Some(builtin_retract(engine, args))
    "clause" if n == 2 => Some(builtin_clause(engine, args))
    "listing" if n == 0 => {
      for _, pc in engine.program.preds {
        for c in pc.statics {
          println(format_clause(c))
        }
        for c in pc.dynamics {
          println(format_clause(c))
        }
      }
      Some(true)
    }
    // ---------- I/O ----------
    "write" if n == 1 => {
      println(format_term(engine.subst.deref(args[0])))
      Some(true)
    }
    "writeln" if n == 1 => {
      println(format_term(engine.subst.deref(args[0])))
      Some(true)
    }
    "nl" if n == 0 => {
      println("")
      Some(true)
    }
    // ---------- 收集 ----------
    "findall" if n == 3 => Some(builtin_findall(engine, args))
    _ => None
  }
}

///|
fn builtin_functor(engine : Engine, args : Array[LoveTerm]) -> Bool {
  let t = engine.subst.deref(args[0])
  let fun = engine.subst.deref(args[1])
  let ar = engine.subst.deref(args[2])
  match t {
    LoveTerm::Var(_) =>
      match (fun, ar) {
        (LoveTerm::Atom(nm), LoveTerm::Int(a)) if a >= 0L && a <= 64L =>
          if a == 0L {
            unify(engine.subst, t, LoveTerm::Atom(nm))
          } else {
            let fresh : Array[LoveTerm] = []
            for _ in 0..<a.to_int() {
              fresh.push(LoveTerm::Var(engine.fresh_var()))
            }
            unify(engine.subst, t, LoveTerm::Struct(nm, fresh))
          }
        (LoveTerm::Int(v), LoveTerm::Int(a)) if a == 0L =>
          unify(engine.subst, t, LoveTerm::Int(v))
        (LoveTerm::Float(v), LoveTerm::Int(a)) if a == 0L =>
          unify(engine.subst, t, LoveTerm::Float(v))
        _ => false
      }
    LoveTerm::Int(_)
    | LoveTerm::Float(_)
    | LoveTerm::Atom(_)
    | LoveTerm::Str(_)
    | LoveTerm::ListNil =>
      unify(engine.subst, fun, t) && unify(engine.subst, ar, LoveTerm::Int(0L))
    LoveTerm::Struct(nm, targs) =>
      unify(engine.subst, fun, LoveTerm::Atom(nm)) &&
      unify(engine.subst, ar, LoveTerm::Int(targs.length().to_int64()))
    LoveTerm::ListCons(_, _) =>
      unify(engine.subst, fun, LoveTerm::Atom(".")) &&
      unify(engine.subst, ar, LoveTerm::Int(2L))
  }
}

///|
fn builtin_arg(engine : Engine, args : Array[LoveTerm]) -> Bool {
  let idx = engine.subst.deref(args[0])
  let t = engine.subst.deref(args[1])
  match (idx, t) {
    (LoveTerm::Int(i), LoveTerm::Struct(_, targs)) if i >= 1L &&
      i <= targs.length().to_int64() =>
      unify(engine.subst, args[2], targs[i.to_int() - 1])
    _ => false
  }
}

///|
fn builtin_univ(engine : Engine, args : Array[LoveTerm]) -> Bool {
  let t = engine.subst.deref(args[0])
  let l = engine.subst.deref(args[1])
  match t {
    LoveTerm::Var(_) =>
      match flatten_proper_list(l) {
        None => false
        Some(elems) =>
          if elems.is_empty() {
            false
          } else {
            let fun = engine.subst.deref(elems[0])
            let rest = elems[1:]
            match (fun, rest.length()) {
              (LoveTerm::Atom(nm), 0) =>
                unify(engine.subst, t, LoveTerm::Atom(nm))
              (LoveTerm::Atom(nm), _) =>
                unify(engine.subst, t, LoveTerm::Struct(nm, rest.to_owned()))
              (LoveTerm::Int(v), 0) => unify(engine.subst, t, LoveTerm::Int(v))
              (LoveTerm::Float(v), 0) =>
                unify(engine.subst, t, LoveTerm::Float(v))
              _ => false
            }
          }
      }
    LoveTerm::Atom(nm) => unify(engine.subst, l, list_of([LoveTerm::Atom(nm)]))
    LoveTerm::Int(v) => unify(engine.subst, l, list_of([LoveTerm::Int(v)]))
    LoveTerm::Float(v) => unify(engine.subst, l, list_of([LoveTerm::Float(v)]))
    LoveTerm::Str(s) => unify(engine.subst, l, list_of([LoveTerm::Str(s)]))
    LoveTerm::Struct(nm, targs) => {
      let elems : Array[LoveTerm] = [LoveTerm::Atom(nm)]
      for a in targs {
        elems.push(a)
      }
      unify(engine.subst, l, list_of(elems))
    }
    _ => false
  }
}

///|
fn builtin_atom_length(engine : Engine, args : Array[LoveTerm]) -> Bool {
  match engine.subst.deref(args[0]) {
    LoveTerm::Atom(s) | LoveTerm::Str(s) =>
      unify(engine.subst, args[1], LoveTerm::Int(s.length().to_int64()))
    _ => false
  }
}

///|
fn builtin_atom_concat(engine : Engine, args : Array[LoveTerm]) -> Bool {
  let a1 = engine.subst.deref(args[0])
  let a2 = engine.subst.deref(args[1])
  let a3 = engine.subst.deref(args[2])
  match (a1, a2, a3) {
    (LoveTerm::Atom(x), LoveTerm::Atom(y), LoveTerm::Atom(z)) => x + y == z
    (LoveTerm::Atom(x), LoveTerm::Atom(y), LoveTerm::Var(_)) =>
      unify(engine.subst, a3, LoveTerm::Atom(x + y))
    (LoveTerm::Atom(x), LoveTerm::Var(_), LoveTerm::Atom(z)) =>
      if z.has_prefix(x) {
        let (_, rest) = z.split_at(x.length())
        unify(engine.subst, a2, LoveTerm::Atom(rest.to_owned()))
      } else {
        false
      }
    (LoveTerm::Var(_), LoveTerm::Atom(y), LoveTerm::Atom(z)) =>
      if z.has_suffix(y) {
        let (head, _) = z.split_at(z.length() - y.length())
        unify(engine.subst, a1, LoveTerm::Atom(head.to_owned()))
      } else {
        false
      }
    // 两个变量 + 一个原子需要枚举所有切分：v0.1 不支持
    _ => false
  }
}

///|
fn builtin_sub_atom(engine : Engine, args : Array[LoveTerm]) -> Bool {
  match engine.subst.deref(args[0]) {
    LoveTerm::Atom(s) | LoveTerm::Str(s) => {
      let len = s.length()
      let before = engine.subst.deref(args[1])
      let length = engine.subst.deref(args[2])
      let after = engine.subst.deref(args[3])
      match (before, length, after) {
        (LoveTerm::Int(b), LoveTerm::Int(l), LoveTerm::Int(a2)) =>
          if b >= 0L && l >= 0L && a2 >= 0L && b + l + a2 == len.to_int64() {
            unify_sub_atom_middle(engine, s, b, l, args[4])
          } else {
            false
          }
        (LoveTerm::Int(b), LoveTerm::Int(l), LoveTerm::Var(_)) => {
          let a2 = len.to_int64() - b - l
          if b >= 0L && l >= 0L && a2 >= 0L {
            unify(engine.subst, args[3], LoveTerm::Int(a2)) &&
            unify_sub_atom_middle(engine, s, b, l, args[4])
          } else {
            false
          }
        }
        (LoveTerm::Int(b), LoveTerm::Var(_), LoveTerm::Int(a2)) => {
          let l = len.to_int64() - b - a2
          if b >= 0L && a2 >= 0L && l >= 0L {
            unify(engine.subst, args[2], LoveTerm::Int(l)) &&
            unify_sub_atom_middle(engine, s, b, l, args[4])
          } else {
            false
          }
        }
        _ => false
      }
    }
    _ => false
  }
}

///|
/// 按 before/length 提取子串并与第 4 个参数合一。
fn unify_sub_atom_middle(
  engine : Engine,
  s : String,
  b : Int64,
  l : Int64,
  out : LoveTerm,
) -> Bool {
  let start = b.to_int()
  let end = (b + l).to_int()
  if start >= 0 && end <= s.length() {
    let (_, rest) = s.split_at(start)
    let (mid, _) = rest.split_at(end - start)
    unify(engine.subst, out, LoveTerm::Atom(mid.to_owned()))
  } else {
    false
  }
}

///|
fn builtin_between(engine : Engine, args : Array[LoveTerm]) -> Bool {
  let lo = engine.subst.deref(args[0])
  let hi = engine.subst.deref(args[1])
  let x = engine.subst.deref(args[2])
  match (lo, hi, x) {
    (LoveTerm::Int(l), LoveTerm::Int(h), LoveTerm::Var(_)) =>
      if l > h {
        false
      } else {
        engine.cps.push({
          trail_len: engine.subst.trail.length(),
          goals_snapshot: snapshot_goals(engine.goals),
          kind: CPKind::EnumInt(l + 1L, h, args[2]),
        })
        unify(engine.subst, args[2], LoveTerm::Int(l))
      }
    (LoveTerm::Int(l), LoveTerm::Int(h), LoveTerm::Int(v)) => v >= l && v <= h
    _ => false
  }
}

///|
fn builtin_plus(engine : Engine, args : Array[LoveTerm]) -> Bool {
  let a = engine.subst.deref(args[0])
  let b = engine.subst.deref(args[1])
  let c = engine.subst.deref(args[2])
  match (a, b, c) {
    (LoveTerm::Int(x), LoveTerm::Int(y), _) =>
      unify(engine.subst, args[2], LoveTerm::Int(x + y))
    (LoveTerm::Int(x), _, LoveTerm::Int(z)) =>
      unify(engine.subst, args[1], LoveTerm::Int(z - x))
    (_, LoveTerm::Int(y), LoveTerm::Int(z)) =>
      unify(engine.subst, args[0], LoveTerm::Int(z - y))
    _ => false
  }
}

///|
fn builtin_sort(engine : Engine, args : Array[LoveTerm], dedup : Bool) -> Bool {
  let l = engine.subst.deref(args[0])
  match flatten_proper_list(l) {
    None => false
    Some(raw) => {
      let deref_elems = raw.map(fn(e) { engine.subst.deref(e) })
      let sorted = merge_sort(deref_elems, engine.subst)
      let final_elems = if dedup {
        dedup_sorted(sorted, engine.subst)
      } else {
        sorted
      }
      unify(engine.subst, args[1], list_of(final_elems))
    }
  }
}

///|
fn builtin_maplist(engine : Engine, args : Array[LoveTerm], f : Frame) -> Bool {
  let g = engine.subst.deref(args[0])
  let l = engine.subst.deref(args[1])
  match flatten_proper_list(l) {
    None => false
    Some(elems) => {
      let mut conj = LoveTerm::Atom("true")
      for i = elems.length() - 1; i >= 0; i = i - 1 {
        let goal_i = apply_goal(g, elems[i])
        conj = LoveTerm::Struct(",", [goal_i, conj])
      }
      engine.goals.push({ term: conj, ci: 0, barrier: f.barrier })
      true
    }
  }
}

///|
fn apply_goal(g : LoveTerm, elem : LoveTerm) -> LoveTerm {
  match g {
    LoveTerm::Atom(nm) => LoveTerm::Struct(nm, [elem])
    LoveTerm::Struct(nm, gargs) => {
      // 复制参数数组，避免污染原项
      let args = gargs.map(fn(x) { x })
      args.push(elem)
      LoveTerm::Struct(nm, args)
    }
    _ => LoveTerm::Atom("fail")
  }
}

///|
fn builtin_retract(engine : Engine, args : Array[LoveTerm]) -> Bool {
  let target = engine.subst.deref(args[0])
  let name = match target {
    LoveTerm::Atom(n) => Some(n)
    LoveTerm::Struct(n, _) => Some(n)
    _ => None
  }
  match name {
    None => false
    Some(nm) =>
      match engine.program.preds.get(nm) {
        None => false
        Some(pc) => {
          let mut found = -1
          for i in 0..<pc.dynamics.length() {
            if found >= 0 {
              break
            }
            let c = pc.dynamics[i]
            let (head, _) = fresh_clause_vars(engine, c)
            if unify(engine.subst, target, head) {
              found = i
            }
          }
          if found >= 0 {
            let _ = pc.dynamics.remove(found)
            true
          } else {
            false
          }
        }
      }
  }
}

///|
fn builtin_clause(engine : Engine, args : Array[LoveTerm]) -> Bool {
  let all = engine.program.all_clauses()
  let base = engine.subst.trail.length()
  let mut idx = 0
  let mut ok = false
  while idx < all.length() {
    let c = all[idx]
    let (head, body) = fresh_clause_vars(engine, c)
    if unify(engine.subst, args[0], head) && unify(engine.subst, args[1], body) {
      engine.cps.push({
        trail_len: base,
        goals_snapshot: snapshot_goals(engine.goals),
        kind: CPKind::ClauseScan(idx + 1, args[0], args[1], all),
      })
      ok = true
      break
    }
    engine.subst.unbind_to(base)
    idx += 1
  }
  ok
}

///|
fn builtin_findall(engine : Engine, args : Array[LoveTerm]) -> Bool {
  let tpl = engine.subst.deref(args[0])
  let goal = engine.subst.deref(args[1])
  let (copies, new_counter) = copy_fresh(engine, [tpl, goal])
  let tpl_copy = copies[0]
  let goal_copy = copies[1]
  let sub = Engine::new(engine.program, new_counter, goal_copy)
  let results : Array[LoveTerm] = []
  for ;; {
    match sub.solve_next() {
      None => break
      Some(_) => {
        let inst = sub.subst.deref(tpl_copy)
        let (copies2, _) = copy_fresh(engine, [inst])
        results.push(copies2[0])
      }
    }
  }
  engine.var_counter = if engine.var_counter > sub.var_counter {
    engine.var_counter
  } else {
    sub.var_counter
  }
  unify(engine.subst, args[2], list_of(results))
}

///|
/// 把若干项复制到全新变量空间（findall 用）。
fn copy_fresh(
  engine : Engine,
  terms : Array[LoveTerm],
) -> (Array[LoveTerm], Int) {
  let ids : Array[Int] = []
  for t in terms {
    collect_var_ids(t, ids)
  }
  let m : Map[Int, Int] = Map([])
  for i in 0..<ids.length() {
    m[ids[i]] = engine.var_counter + i
  }
  engine.var_counter += ids.length()
  let out = terms.map(fn(t) { replace_vars(t, m) })
  (out, engine.var_counter)
}

///|
/// 规范列表 → 元素数组；非规范列表或非列表返回 None。
fn flatten_proper_list(t : LoveTerm) -> Array[LoveTerm]? {
  let out : Array[LoveTerm] = []
  let mut cur = t
  for ;; {
    match cur {
      LoveTerm::ListNil => return Some(out)
      LoveTerm::ListCons(h, tl) => {
        out.push(h)
        cur = tl
      }
      _ => return None
    }
  }
}

///|
/// 标准项序：Var < Int < Float < Atom < Str < Struct < ListCons < ListNil。
fn term_order(subst : Subst, a : LoveTerm, b : LoveTerm) -> Int {
  let x = subst.deref(a)
  let y = subst.deref(b)
  match (x, y) {
    (LoveTerm::Var(i), LoveTerm::Var(j)) => i.compare(j)
    (LoveTerm::Var(_), _) => -1
    (_, LoveTerm::Var(_)) => 1
    (LoveTerm::Int(i), LoveTerm::Int(j)) => i.compare(j)
    (LoveTerm::Float(f), LoveTerm::Float(g)) =>
      if f < g {
        -1
      } else if f > g {
        1
      } else {
        0
      }
    (LoveTerm::Int(i), LoveTerm::Float(f)) => {
      let d = i.to_double()
      if d < f {
        -1
      } else if d > f {
        1
      } else {
        0
      }
    }
    (LoveTerm::Float(f), LoveTerm::Int(i)) => {
      let d = i.to_double()
      if f < d {
        -1
      } else if f > d {
        1
      } else {
        0
      }
    }
    (LoveTerm::Atom(s1), LoveTerm::Atom(s2)) => s1.compare(s2)
    (LoveTerm::Str(s1), LoveTerm::Str(s2)) => s1.compare(s2)
    (LoveTerm::Struct(n1, a1), LoveTerm::Struct(n2, a2)) =>
      if n1 != n2 {
        n1.compare(n2)
      } else if a1.length() != a2.length() {
        a1.length() - a2.length()
      } else {
        for i in 0..<a1.length() {
          let c = term_order(subst, a1[i], a2[i])
          if c != 0 {
            return c
          }
        }
        0
      }
    (LoveTerm::ListCons(h1, t1), LoveTerm::ListCons(h2, t2)) => {
      let c = term_order(subst, h1, h2)
      if c != 0 {
        c
      } else {
        term_order(subst, t1, t2)
      }
    }
    (LoveTerm::ListNil, LoveTerm::ListNil) => 0
    _ => term_rank(x) - term_rank(y)
  }
}

///|
fn term_rank(t : LoveTerm) -> Int {
  match t {
    LoveTerm::Var(_) => 0
    LoveTerm::Int(_) => 1
    LoveTerm::Float(_) => 2
    LoveTerm::Atom(_) => 3
    LoveTerm::Str(_) => 4
    LoveTerm::Struct(_, _) => 5
    LoveTerm::ListCons(_, _) => 6
    LoveTerm::ListNil => 7
  }
}

///|
/// 归并排序（稳定）。
fn merge_sort(xs : Array[LoveTerm], subst : Subst) -> Array[LoveTerm] {
  if xs.length() <= 1 {
    return xs
  }
  let mid = xs.length() / 2
  let left = merge_sort(xs[0:mid].to_owned(), subst)
  let right = merge_sort(xs[mid:].to_owned(), subst)
  let out : Array[LoveTerm] = []
  let mut i = 0
  let mut j = 0
  while i < left.length() && j < right.length() {
    if term_order(subst, left[i], right[j]) <= 0 {
      out.push(left[i])
      i += 1
    } else {
      out.push(right[j])
      j += 1
    }
  }
  while i < left.length() {
    out.push(left[i])
    i += 1
  }
  while j < right.length() {
    out.push(right[j])
    j += 1
  }
  out
}

///|
/// 去除相邻重复（sort/2 用）。
fn dedup_sorted(xs : Array[LoveTerm], subst : Subst) -> Array[LoveTerm] {
  let out : Array[LoveTerm] = []
  for x in xs {
    if out.is_empty() || term_order(subst, out[out.length() - 1], x) != 0 {
      out.push(x)
    }
  }
  out
}
