use magnus::{define_module, function, prelude::*, Error};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs;
use std::path::{Component, Path, PathBuf};

const MAX_WORKFLOW_BYTES: u64 = 1_048_576;
const MAX_WORKFLOW_STEPS: usize = 100;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Workflow {
    name: String,
    version: u64,
    #[serde(default)]
    description: Option<String>,
    steps: Vec<Step>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Step {
    id: String,
    uses: String,
    #[serde(default)]
    with: BTreeMap<String, Value>,
}

#[derive(Debug, Serialize)]
struct ValidatedWorkflow {
    name: String,
    version: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    description: Option<String>,
    steps: Vec<ValidatedStep>,
}

#[derive(Debug, Serialize)]
struct ValidatedStep {
    id: String,
    uses: String,
    with: BTreeMap<String, Value>,
    approval_required: bool,
}

#[magnus::init]
fn init() -> Result<(), Error> {
    let module = define_module("WorkflowSafety")?;
    module.define_singleton_method("validate_file", function!(validate_file, 3))?;
    Ok(())
}

fn validate_file(root: String, name: String, handler_risks_json: String) -> String {
    let result = validate_workflow_file(&root, &name, &handler_risks_json);
    match result {
        Ok(workflow) => json!({ "ok": true, "workflow": workflow }).to_string(),
        Err(message) => json!({ "ok": false, "error": message }).to_string(),
    }
}

fn validate_workflow_file(
    root: &str,
    name: &str,
    handler_risks_json: &str,
) -> Result<ValidatedWorkflow, String> {
    let risks: HashMap<String, String> = serde_json::from_str(handler_risks_json)
        .map_err(|error| format!("invalid handler policy: {error}"))?;

    for (handler, risk) in &risks {
        if handler.trim().is_empty() {
            return Err("handler names must not be empty".to_owned());
        }
        if !matches!(risk.as_str(), "low" | "medium" | "high") {
            return Err(format!(
                "invalid risk level {risk:?} for handler {handler:?}"
            ));
        }
    }

    let workflow_path = resolve_workflow_path(root, name)?;
    let metadata = fs::metadata(&workflow_path)
        .map_err(|error| format!("cannot inspect workflow: {error}"))?;
    if !metadata.is_file() {
        return Err("workflow path is not a regular file".to_owned());
    }
    if metadata.len() > MAX_WORKFLOW_BYTES {
        return Err(format!(
            "workflow exceeds the {} byte limit",
            MAX_WORKFLOW_BYTES
        ));
    }

    let source = fs::read_to_string(&workflow_path)
        .map_err(|error| format!("cannot read workflow: {error}"))?;
    let workflow: Workflow =
        serde_yaml::from_str(&source).map_err(|error| format!("invalid workflow YAML: {error}"))?;

    if workflow.name.trim().is_empty() {
        return Err("workflow name must be a non-empty String".to_owned());
    }
    if workflow.version == 0 {
        return Err("workflow version must be a positive Integer".to_owned());
    }
    if workflow
        .description
        .as_ref()
        .map(|description| !description.is_empty() && description.trim().is_empty())
        .unwrap_or(false)
    {
        return Err("workflow description must not contain only whitespace".to_owned());
    }
    if workflow.steps.is_empty() {
        return Err("workflow steps must be a non-empty Array".to_owned());
    }
    if workflow.steps.len() > MAX_WORKFLOW_STEPS {
        return Err(format!(
            "workflow exceeds the {} step limit",
            MAX_WORKFLOW_STEPS
        ));
    }

    let mut ids = HashSet::new();
    let mut validated_steps = Vec::with_capacity(workflow.steps.len());
    for (index, step) in workflow.steps.into_iter().enumerate() {
        if step.id.trim().is_empty() {
            return Err(format!("step {index} id must be a non-empty String"));
        }
        if !ids.insert(step.id.clone()) {
            return Err(format!("duplicate step id {:?}", step.id));
        }
        if step.uses.trim().is_empty() {
            return Err(format!(
                "step {:?} uses must be a non-empty String",
                step.id
            ));
        }
        let risk = risks
            .get(&step.uses)
            .ok_or_else(|| format!("handler {:?} is not allowlisted", step.uses))?;

        validated_steps.push(ValidatedStep {
            id: step.id,
            uses: step.uses,
            with: step.with,
            approval_required: risk != "low",
        });
    }

    Ok(ValidatedWorkflow {
        name: workflow.name,
        version: workflow.version,
        description: workflow.description,
        steps: validated_steps,
    })
}

fn resolve_workflow_path(root: &str, name: &str) -> Result<PathBuf, String> {
    if name.trim().is_empty() {
        return Err("workflow name must be a non-empty String".to_owned());
    }

    let root = Path::new(root)
        .canonicalize()
        .map_err(|error| format!("cannot resolve workflow directory: {error}"))?;
    let requested = Path::new(name);
    if requested.is_absolute()
        || requested.components().any(|component| {
            matches!(
                component,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        })
    {
        return Err(
            "workflow path must be relative and cannot traverse parent directories".to_owned(),
        );
    }

    let mut relative = requested.to_path_buf();
    match relative
        .extension()
        .and_then(|extension| extension.to_str())
    {
        Some("yml") | Some("yaml") => {}
        Some(_) => return Err("workflow file extension must be .yml or .yaml".to_owned()),
        None => {
            relative.set_extension("yml");
        }
    }

    let path = root
        .join(relative)
        .canonicalize()
        .map_err(|error| format!("workflow not found: {error}"))?;
    if !path.starts_with(&root) {
        return Err("workflow path resolves outside the workflow directory".to_owned());
    }
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    struct TempDirectory(PathBuf);

    impl TempDirectory {
        fn new() -> Self {
            let unique = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system clock should be after Unix epoch")
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "ruby-orchestrator-safety-{}-{unique}",
                std::process::id()
            ));
            fs::create_dir_all(&path).expect("temporary directory should be created");
            Self(path)
        }

        fn write(&self, name: &str, contents: &str) {
            fs::write(self.0.join(name), contents).expect("workflow fixture should be written");
        }
    }

    impl Drop for TempDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn validates_allowlisted_workflow_and_marks_approval() {
        let directory = TempDirectory::new();
        directory.write(
            "safe.yml",
            "name: safe\nversion: 1\nsteps:\n  - id: read\n    uses: mcp.read\n",
        );
        let result = validate_workflow_file(
            directory.0.to_str().unwrap(),
            "safe",
            r#"{"mcp.read":"high"}"#,
        )
        .unwrap();

        assert!(result.steps[0].approval_required);
    }

    #[test]
    fn rejects_unallowlisted_handler() {
        let directory = TempDirectory::new();
        directory.write(
            "unsafe.yml",
            "name: unsafe\nversion: 1\nsteps:\n  - id: run\n    uses: shell.exec\n",
        );

        let error = validate_workflow_file(
            directory.0.to_str().unwrap(),
            "unsafe",
            r#"{"mcp.read":"low"}"#,
        )
        .unwrap_err();

        assert!(error.contains("not allowlisted"));
    }

    #[test]
    fn rejects_path_traversal() {
        let directory = TempDirectory::new();

        let error =
            resolve_workflow_path(directory.0.to_str().unwrap(), "../secret.yml").unwrap_err();

        assert!(error.contains("cannot traverse"));
    }
}
