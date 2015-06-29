subroutine react(Xin, T, rho, tmax, Xout, enucdot)

  use network
  use rpar_indices

  implicit none

  ! do a simple first-order backward Euler method for integrating
  ! a stiff-system of ODEs.

  ! Note: this should not been seen as a science code, but rather
  ! just used to test ideas about putting reactions on GPUs

  ! this version works on a single-zone only

  double precision, dimension(nspec), intent(in) :: Xin
  double precision, dimension(nspec), intent(out) :: Xout
  double precision, intent(in) :: T, rho, tmax
  double precision, intent(out) :: enucdot

  double precision :: time, dt, I

  integer :: m, n
    
  double precision :: dXdt(nspec)
  double precision :: X1(nspec), X2(nspec), dX1dt(nspec), dX2dt(nspec)
  double precision :: X_n(nspec), X_np1(nspec), dX(nspec), dfdX(nspec)
  double precision :: A(nspec, nspec), J(nspec, nspec), b(nspec)
  integer :: info
  
  double precision, parameter :: eps = 1.d-8

  double precision :: rpar(n_rpar_comps)
  integer :: ipar

  integer :: ipiv(nspec)

  double precision, parameter :: tol = 1.d-4
  integer, parameter :: max_iter = 10
  integer :: iter
  logical :: converged
  

  ! get an estimate of the timestep by looking at the RHS
  ! dt = min{X/(dX/dt)}
  rpar(irp_dens) = rho
  rpar(irp_temp) = T

  call rhs(nspec, 0.0d0, Xin, dXdt, rpar, ipar)
  print *, dXdt

  dt = 1.d33
  dt = 0.1*min(dt, abs(Xin(ih1)/dXdt(ih1)))

  print *, "dt = ", dt


  X_n(:) = Xin(:)
  
  ! do the integration
  time = 0.0d0
  do while (time < tmax)

     print *, time

     converged = .false.

     ! initial guess
     X_np1(:) = X_n(:)
     
     do iter = 1, max_iter

        ! construct a numerical Jacobian via simple differencing
        ! Lapack matrix ordering is described here:
        ! http://www.netlib.org/lapack/lug/node116.html#subsecarrayargs
        ! in general, A(i,j) holds matrix element a_{i,j}
        
        ! J_{m,n} = df_m/dX_n
        do n = 1, nspec
           X1(:) = X_np1(:)
           X1(n) = X1(n) + eps
           
           X2(:) = X_np1(:)
           X2(n) = X2(n) - eps
           
           call rhs(nspec, 0.0d0, X1, dX1dt, rpar, ipar)
           call rhs(nspec, 0.0d0, X2, dX2dt, rpar, ipar)
           
           do m = 1, nspec
              J(m,n) = 0.5d0*(dX2dt(m) - dX1dt(m))/(X2(n) - X1(n))
           enddo
        enddo

        ! construct the matrix for the linear system
        ! (I - dt J) dX^{n+1} = rhs
        do n = 1, nspec
           do m = 1, nspec
              if (m == n) then
                 I = 1.0d0
              else
                 I = 0.0d0
              endif
              
              A(m,n) = I - dt*J(m,n)
           enddo
        enddo
        
        ! construct the RHS
        call rhs(nspec, 0.0d0, X_np1, dXdt, rpar, ipar)
        b(:) = X_n(:) - X_np1(:) + dt*dXdt(:)
     
        ! solve the linear system -- we'll just use Lapack.  Note that the
        ! input b is overwritten on output
        call dgesv(nspec, 1, A, nspec, ipiv, b, nspec, info)

        dX(:) = b(:)

        X_np1(:) = X_np1(:) + dX(:)
        
        ! compare to see if we converged
        if (abs(dX(ih1)) < tol*X_n(ih1)) then
           converged = .true.
           exit
        endif

     enddo   ! dX iteration loop

     if (.not. converged) then
        print *, abs(dx(ih1)), X_n(ih1), abs(dx(ih1))/X_n(ih1)
        stop 'convergence failure'
     endif
        
     if (time + dt > tmax) then
        dt = tmax - time
     endif

     X_n(:) = X_np1(:)
     time = time + dt
  enddo

  Xout(:) = X_n(:)

end subroutine react