from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'App/FamilyNewsApp.swift').read_text()
gate=source[source.index('@MainActor final class BiometricGate:'):source.index('struct BiometricLockScreen:')]
stubs=r'''
import Foundation
protocol ObservableObject {}
@propertyWrapper struct Published<Value> {var wrappedValue:Value;init(wrappedValue:Value){self.wrappedValue=wrappedValue}}
enum LAPolicy {case deviceOwnerAuthenticationWithBiometrics}
struct LAError:Error {enum Code {case userCancel,systemCancel,appCancel,authenticationFailed};let code:Code}
@MainActor enum CredentialStore {static var saved=true;static func hasSession()->Bool{saved}}
@MainActor final class Backend {
 var signedIn=false;var restoring=true;var warning="";var restored=0;var loaded=0
 func restore()async{restored += 1;signedIn=CredentialStore.saved;restoring=false}
 func loadAccount()async throws{loaded += 1}
 func clearSession(){signedIn=false;CredentialStore.saved=false}
 func errorText(_ error:Error)->String{error.localizedDescription}
}
@MainActor final class LAContext {
 enum Kind {case touchID,faceID,none}
 static var available=true;static var cancel=false;static var hold=false;static var calls=0
 static var continuation:CheckedContinuation<Bool,Error>?
 var biometryType:Kind{Self.available ? .faceID:.none}
 var localizedCancelTitle:String?;var localizedFallbackTitle:String?;var touchIDAuthenticationAllowableReuseDuration:Double=0
 func canEvaluatePolicy(_ policy:LAPolicy,error:inout NSError?)->Bool{Self.available}
 func evaluatePolicy(_ policy:LAPolicy,localizedReason:String)async throws->Bool{
  Self.calls += 1;precondition(touchIDAuthenticationAllowableReuseDuration==0)
  if Self.cancel{throw LAError(code:.userCancel)}
  if Self.hold{return try await withCheckedThrowingContinuation{Self.continuation=$0}}
  return true
 }
 func invalidate(){}
}
'''
tests=r'''
@MainActor func runChecks()async {
 let api=Backend();let gate=BiometricGate()
 await gate.start(api);precondition(gate.unlocked && api.restored==1 && LAContext.calls==1,"Cold start authenticates before restoring")
 gate.lock();precondition(!gate.unlocked);await gate.open(api);precondition(gate.unlocked && LAContext.calls==2,"Foreground return requires a fresh attempt")
 gate.lock();LAContext.cancel=true;await gate.open(api);let calls=LAContext.calls;precondition(!gate.unlocked,"Cancel stays locked")
 await gate.open(api);precondition(LAContext.calls==calls,"Cancel must not trigger an automatic prompt loop")
 LAContext.cancel=false;await gate.open(api,automatic:false);precondition(gate.unlocked,"Explicit retry unlocks")
 gate.lock();LAContext.hold=true
 let task=Task{@MainActor in await gate.open(api)}
 while LAContext.continuation==nil{await Task.yield()}
 gate.lock();LAContext.continuation?.resume(returning:true);LAContext.continuation=nil;await task.value
 precondition(!gate.unlocked,"A successful old callback cannot unlock after backgrounding")
 LAContext.hold=false;LAContext.available=false;CredentialStore.saved=true
 let otherAPI=Backend();let unavailable=BiometricGate();await unavailable.start(otherAPI)
 precondition(!unavailable.unlocked && otherAPI.restored==0,"Unavailable biometrics cannot restore a saved session")
 unavailable.passwordLogin(otherAPI);precondition(!CredentialStore.saved && !otherAPI.signedIn)
 otherAPI.signedIn=true;CredentialStore.saved=true;await unavailable.afterPasswordLogin(otherAPI)
 precondition(unavailable.unlocked,"A freshly verified password is the fallback when biometrics are unavailable")
 print("PASS: biometric cold start, re-entry, cancellation, explicit retry, stale callback rejection and fresh-password fallback")
}
await runChecks()
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder)/'biometric-checks.swift';p.write_text(stubs+'\n'+gate+'\n'+tests)
 subprocess.run(['swift',str(p)],check=True,timeout=90)
