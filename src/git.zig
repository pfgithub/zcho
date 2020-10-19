// z git clone [url]
// z git stage
// z git commit [message]
// z git status (unstaged, staged, recent commits)
// z git goto head - 1
// z git reset head - 1
// z git push
// z git pull (merge/rebase)
// z git branch [--new] [name]

// z git status
// == Unstaged Changes ========== [↓] = //
//  +  src/git.zig                      //
//  ~  src/zigsh.zig                    //
//  -  src/deleted.zig                  //
//                                      //
//                                      //
//                                      //
// == Staged Changes ============ [↑] = //
//  *No changes*                        //
//                                      //
//                                      //
//                                      //
//                                      //
//                                      //
// [ Commit to master ]                 //
// == Recent Commits ================== //
//  10d  feat: add new feature    [u]   //
//  11d  bug: fix bug                   //
//                                      //
//                                      //
//                                      //

// it could even be a gui maybe where you can click the stage all button idk