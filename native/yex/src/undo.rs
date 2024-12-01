use rustler::{Env, NifTaggedEnum, ResourceArc, NifStruct, Term, LocalPid, Encoder, NifResult};
use crate::NifError;
use std::sync::RwLock;
use yrs::{UndoManager, undo::Options as UndoOptions};
use crate::{
    text::NifText,
    array::NifArray,
    map::NifMap,
    shared_type::NifSharedType,  
    wrap::NifWrap,
    NifDoc,
    utils::term_to_origin_binary,
    ENV,
    subscription::SubscriptionResource,
    atoms,
};
use std::cell::RefCell;
use std::sync::Mutex;

thread_local! {
    static CURRENT_ENV: RefCell<Option<Env<'static>>> = RefCell::new(None);
}

#[derive(NifTaggedEnum)]
pub enum SharedTypeInput {
    Text(NifText),
    Array(NifArray),
    Map(NifMap),
}

#[derive(NifStruct)]
#[module = "Yex.UndoManager.StackItem"]
pub struct NifStackItem<'a> {
    pub meta: Term<'a>,
}

#[derive(NifStruct)]
#[module = "Yex.UndoManager"]
pub struct NifUndoManager {
    reference: ResourceArc<UndoManagerResource>,
}

pub struct UndoManagerWrapper {
    pub manager: UndoManager,
    pub observer_pid: Option<LocalPid>
}

impl UndoManagerWrapper {
    pub fn new(manager: UndoManager) -> Self {
        Self { 
            manager,
            observer_pid: None
        }
    }
}

pub type UndoManagerResource = NifWrap<RwLock<UndoManagerWrapper>>;

#[rustler::resource_impl]
impl rustler::Resource for UndoManagerResource {}

#[derive(NifStruct)]
#[module = "Yex.UndoManager.Options"]
#[derive(Debug)]
pub struct NifUndoOptions {
    pub capture_timeout: u64,
}

#[derive(NifStruct)]
#[module = "Yex.UndoManager.Event"]
pub struct NifUndoEvent<'a> {
    pub meta: Term<'a>,
    pub stack_item_id: i64,
}

#[derive(NifTaggedEnum)]
pub enum UndoScope {
    Text(NifText),
    Array(NifArray),
    Map(NifMap),
}

fn with_write_lock_if<F, G>(
    env: Env,
    undo_manager: &NifUndoManager,
    predicate: F,
    action: G
) -> Result<(), NifError>
where
    F: FnOnce(&UndoManager) -> bool,
    G: FnOnce(&mut UndoManager) -> bool,
{
    let mut wrapper = undo_manager.reference.0.write()
        .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
    
    if predicate(&wrapper.manager) {
        let result = action(&mut wrapper.manager);
        
        if result {
            notify_observers(env, &wrapper, "popped")?;
        }
    }
    
    Ok(())
}

#[rustler::nif]
pub fn undo_manager_new(
    env: Env<'_>,
    doc: NifDoc,
    scope: SharedTypeInput,
) -> NifResult<Term> {
    ENV.set(&mut env.clone(), || {
        let result = match scope {
            SharedTypeInput::Text(text) => create_undo_manager_with_options(doc, text, NifUndoOptions { capture_timeout: 500 }),
            SharedTypeInput::Array(array) => create_undo_manager_with_options(doc, array, NifUndoOptions { capture_timeout: 500 }),
            SharedTypeInput::Map(map) => create_undo_manager_with_options(doc, map, NifUndoOptions { capture_timeout: 500 }),
        };
        match result {
            Ok(wrapper) => Ok((atoms::ok(), NifUndoManager { reference: wrapper }).encode(env)),
            Err(NifError::Message(msg)) => Ok((atoms::error(), msg).encode(env)),
            Err(NifError::AtomTuple((atom, msg))) => Ok((atoms::error(), (atom, msg)).encode(env))
        }
    })
}



fn create_undo_manager_with_options<T: NifSharedType>(
    doc: NifDoc,
    scope: T,
    options: NifUndoOptions,
) -> Result<ResourceArc<UndoManagerResource>, NifError> {
    let branch = scope.readonly(None, |txn| {
        scope.get_ref(txn)
    }).map_err(|_| NifError::Message("Failed to get branch reference".to_string()))?;
    
    let undo_options = UndoOptions {
        capture_timeout_millis: options.capture_timeout,
        ..Default::default()
    };
    
    let undo_manager = UndoManager::with_scope_and_options(&doc, &branch, undo_options);
    let wrapper = UndoManagerWrapper::new(undo_manager);
    
    Ok(ResourceArc::new(NifWrap(RwLock::new(wrapper))))
}

#[rustler::nif]
pub fn undo_manager_new_with_options(
    env: Env<'_>,
    doc: NifDoc,
    scope: SharedTypeInput,
    options: NifUndoOptions
) -> NifResult<Term> {
    ENV.set(&mut env.clone(), || {
        let result = match scope {
            SharedTypeInput::Text(text) => create_undo_manager_with_options(doc, text, options),
            SharedTypeInput::Array(array) => create_undo_manager_with_options(doc, array, options),
            SharedTypeInput::Map(map) => create_undo_manager_with_options(doc, map, options),
        };
        match result {
            Ok(wrapper) => Ok((atoms::ok(), NifUndoManager { reference: wrapper }).encode(env)),
            Err(NifError::Message(msg)) => Ok((atoms::error(), msg).encode(env)),
            Err(NifError::AtomTuple((atom, msg))) => Ok((atoms::error(), (atom, msg)).encode(env))
        }
    })
}

#[rustler::nif]
pub fn undo_manager_undo(env: Env, undo_manager: NifUndoManager) -> Result<(), NifError> {
    CURRENT_ENV.with(|current_env| {
        *current_env.borrow_mut() = Some(unsafe { std::mem::transmute(env) });
        
        let result = with_write_lock_if(
            env,
            &undo_manager,
            |manager| manager.can_undo(),
            |manager| {
                manager.undo_blocking();
                true
            }
        );
        
        *current_env.borrow_mut() = None;
        result
    })
}

#[rustler::nif]
pub fn undo_manager_redo(env: Env, undo_manager: NifUndoManager) -> Result<(), NifError> {
    with_write_lock_if(
        env,
        &undo_manager,
        |manager| manager.can_redo(),
        |manager| {
            manager.redo_blocking();
            true
        }
    )
}


#[rustler::nif]
pub fn undo_manager_include_origin<'a>(
    env: Env<'a>, 
    undo_manager: NifUndoManager, 
    origin_term: Term<'a>
) -> NifResult<Term<'a>> {
    ENV.set(&mut env.clone(), || {
        println!("DEBUG: Including origin");
        let mut wrapper = match undo_manager.reference.0.write() {
            Ok(w) => w,
            Err(_) => {
                println!("DEBUG: Failed to acquire write lock for include_origin");
                return Ok((atoms::error(), "Failed to acquire write lock").encode(env));
            }
        };
        
        if let Some(origin) = term_to_origin_binary(origin_term) {
            println!("DEBUG: Origin converted successfully");
            wrapper.manager.include_origin(origin.as_slice());
            println!("DEBUG: Origin included in manager");
        } else {
            println!("DEBUG: Failed to convert origin term");
        }
        
        Ok((atoms::ok()).encode(env))
    })
}

#[rustler::nif]
pub fn undo_manager_exclude_origin(
    env: Env<'_>, 
    undo_manager: NifUndoManager, 
    origin_term: Term
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.0.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        if let Ok(origin_str) = origin_term.atom_to_string() {
            wrapper.manager.exclude_origin(origin_str.as_bytes());
            Ok(())
        } else if let Some(binary) = term_to_origin_binary(origin_term) {
            wrapper.manager.exclude_origin(binary.as_slice());
            Ok(())
        } else {
            Err(NifError::Message("Invalid origin type".to_string()))
        }
    })
}

#[rustler::nif]
pub fn undo_manager_expand_scope(
    env: Env<'_>,
    undo_manager: NifUndoManager,
    scope: SharedTypeInput,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.0.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        match scope {
            SharedTypeInput::Text(text) => {
                let branch = text.readonly(None, |txn| text.get_ref(txn))
                    .map_err(|_| NifError::Message("Failed to get text branch reference".to_string()))?;
                wrapper.manager.expand_scope(&branch);
            },
            SharedTypeInput::Array(array) => {
                let branch = array.readonly(None, |txn| array.get_ref(txn))
                    .map_err(|_| NifError::Message("Failed to get array branch reference".to_string()))?;
                wrapper.manager.expand_scope(&branch);
            },
            SharedTypeInput::Map(map) => {
                let branch = map.readonly(None, |txn| map.get_ref(txn))
                    .map_err(|_| NifError::Message("Failed to get map branch reference".to_string()))?;
                wrapper.manager.expand_scope(&branch);
            },
        }
        
        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_stop_capturing(env: Env<'_>, undo_manager: NifUndoManager) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.0.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        wrapper.manager.reset();
        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_clear(env: Env, undo_manager: NifUndoManager) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.0.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        wrapper.manager.clear();
        notify_observers(env, &wrapper, "popped")?;
        
        Ok(())
    })
}

fn notify_observers(env: Env, wrapper: &UndoManagerWrapper, event_type: &str) -> Result<(), NifError> {
    println!("DEBUG: Notifying observers of event: {}", event_type);
    if let Some(pid) = &wrapper.observer_pid {
        println!("DEBUG: Found observer PID");
        env.send(pid, (atoms::stack_item_popped(), event_type))
            .map_err(|_| {
                println!("DEBUG: Failed to send notification");
                NifError::Message("Failed to send notification".to_string())
            })?;
        println!("DEBUG: Successfully sent notification");
    } else {
        println!("DEBUG: No observer PID found");
    }
    Ok(())
}

#[rustler::nif]
pub fn undo_manager_add_added_observer(
    undo_manager: NifUndoManager,
    observer_pid: LocalPid,
) -> Result<ResourceArc<SubscriptionResource>, NifError> {
    let wrapper = undo_manager.reference.0.write()
        .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
    
    let pid = observer_pid.clone();
    
    let subscription = wrapper.manager.observe_item_added(move |_txn, event| {
        let stack_item_id = event.kind() as i64;
        
        // Schedule work to happen in a new NIF environment
        rustler::schedule_nif(
            "handle_undo_event",
            0,
            move |env| {
                // Send event to Elixir and get metadata update back
                let nif_event = NifUndoEvent {
                    meta: event.meta().encode(env),
                    stack_item_id,
                };
                
                // Send event and wait for response with new metadata
                match pid.send_and_await(env, (atoms::stack_item_added(), nif_event))? {
                    Ok(new_meta) => {
                        // Update the metadata in yrs safely
                        *event.meta_mut() = new_meta;
                    },
                    _ => ()
                }
                Ok(atoms::ok())
            },
        );
    });

    Ok(ResourceArc::new(NifWrap(Mutex::new(Some(subscription)))))
}

#[rustler::nif]
pub fn undo_manager_add_updated_observer(
    env: Env,
    undo_manager: NifUndoManager,
    observer_pid: LocalPid,
) -> Result<ResourceArc<SubscriptionResource>, NifError> {
    ENV.set(&mut env.clone(), || {
        let wrapper = undo_manager.reference.0.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        let subscription = wrapper.manager.observe_item_updated(move |txn, event| {
            if let Some(env) = CURRENT_ENV.with(|cell| cell.borrow().clone()) {
                let stack_item_id = event.kind() as i64;
                
                let nif_event = NifUndoEvent {
                    meta: event.meta_mut().encode(env),
                    stack_item_id,
                };
                
                let _ = env.send(&observer_pid, (atoms::stack_item_updated(), nif_event));
            }
        });

        Ok(ResourceArc::new(NifWrap(Mutex::new(Some(subscription)))))
    })
}

#[rustler::nif]
pub fn undo_manager_add_popped_observer(
    env: Env,
    undo_manager: NifUndoManager,
    observer_pid: LocalPid
) -> Result<ResourceArc<SubscriptionResource>, NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.0.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        wrapper.observer_pid = Some(observer_pid.clone());
        
        let subscription = wrapper.manager.observe_item_popped(move |txn, event| {
            if let Some(env) = CURRENT_ENV.with(|cell| cell.borrow().clone()) {
                let stack_item_id = event.kind() as i64;
                
                let nif_event = NifUndoEvent {
                    meta: event.meta_mut().encode(env),
                    stack_item_id,
                };
                
                let _ = env.send(&observer_pid, (atoms::stack_item_popped(), nif_event));
            }
        });

        Ok(ResourceArc::new(NifWrap(Mutex::new(Some(subscription)))))
    })
}




